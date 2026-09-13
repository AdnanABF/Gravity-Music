// Resume, and the cold-start restore — both broken in the first build, both
// invisible to anything but a test that drives the controller the way the
// real engine does.
//
// The fake handler reproduces the two engine behaviours that caused the bugs:
//
//  • `setSourceNPlay` never completes while playing. The real handler awaits
//    just_audio's `play()`, whose future resolves only on pause/stop. The old
//    controller awaited it, so its resume seek never ran → "starts over".
//  • The engine reports 0:00 while a new source loads, and the previous
//    source's playhead is still live at the moment of the switch. The old
//    controller wrote both onto the episode being resumed.

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:saragama/podcast/controllers/podcast_player_controller.dart';
import 'package:saragama/podcast/models/podcast_episode.dart';
import 'package:saragama/podcast/services/podcast_history_service.dart';
import 'package:saragama/podcast/services/podcast_prefs.dart';
import 'package:saragama/shared/media_domain.dart';

/// Minimal stand-in for MyAudioHandler's command bus.
class FakeEngine extends BaseAudioHandler {
  final positions = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];
  final commands = <String>[];
  Map<String, dynamic>? lastRestore;

  /// Held open for the whole "episode", like just_audio's play().
  final _neverEnds = Completer<void>();

  void _state(AudioProcessingState p, {bool playing = false}) =>
      playbackState.add(playbackState.value
          .copyWith(processingState: p, playing: playing));

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    commands.add(name);
    switch (name) {
      case 'setSourceNPlay':
        mediaItem.add(extras!['mediaItem'] as MediaItem);
        _state(AudioProcessingState.loading);
        positions.add(Duration.zero); // mid-load 0:00
        await Future<void>.delayed(const Duration(milliseconds: 20));
        _state(AudioProcessingState.ready, playing: true);
        positions.add(Duration.zero);
        return _neverEnds.future; // ← the trap
      case 'restoreSession':
        lastRestore = extras;
        final items = extras!['items'] as List<MediaItem>;
        mediaItem.add(items.first);
        _state(AudioProcessingState.loading);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        _state(AudioProcessingState.ready);
        return;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    positions.add(position);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
}

PodcastEpisode ep(String id) => PodcastEpisode(
      id: id,
      title: 'Episode $id',
      showId: 'show1',
      showTitle: 'The Diary Of A CEO',
      duration: const Duration(hours: 1),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 250));

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('gm_resume_test');
    Hive.init(dir.path);
    for (final b in ['PodcastHistory', 'PodcastBox', 'AppPrefs']) {
      await Hive.openBox(b);
    }
  });

  setUp(() async {
    for (final b in ['PodcastHistory', 'PodcastBox', 'AppPrefs']) {
      await Hive.box(b).clear();
    }
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  PodcastPlayerController make(FakeEngine engine) {
    final c = PodcastPlayerController(
        audioHandler: engine, positionStream: engine.positions.stream);
    c.onInit(); // ignore: invalid_use_of_protected_member
    return c;
  }

  void seedPosition(PodcastEpisode e, Duration at) {
    PodcastHistoryService.recordStart(e);
    PodcastHistoryService.saveProgress(e, position: at);
  }


  test('resume seeks to the saved position even though play() never returns',
      () async {
    final engine = FakeEngine();
    final c = make(engine);
    seedPosition(ep('B'), const Duration(minutes: 27, seconds: 34));

    // Must return promptly — the old code awaited the never-ending future.
    await c.play(ep('B')).timeout(const Duration(seconds: 1));
    await settle();

    expect(engine.seeks, [const Duration(minutes: 27, seconds: 34)],
        reason: 'the resume seek must run once the source is ready');
    expect(c.position.value, const Duration(minutes: 27, seconds: 34));
  });

  test("the load's 0:00 never overwrites the saved resume point", () async {
    final engine = FakeEngine();
    final c = make(engine);
    seedPosition(ep('B'), const Duration(minutes: 30));

    await c.play(ep('B'));
    await settle();

    expect(PodcastHistoryService.progressFor('B')!.position,
        const Duration(minutes: 30));
  });

  test('switching episodes saves the old one and leaves the new one intact',
      () async {
    final engine = FakeEngine();
    final c = make(engine);
    seedPosition(ep('B'), const Duration(minutes: 30));

    // A plays and reaches 10:00.
    await c.play(ep('A'));
    await settle();
    engine.positions.add(const Duration(minutes: 10));
    await settle();

    // Now switch to B.
    await c.play(ep('B'));
    await settle();

    expect(PodcastHistoryService.progressFor('A')!.position,
        const Duration(minutes: 10),
        reason: "A's final playhead must be persisted before the switch");
    expect(PodcastHistoryService.progressFor('B')!.position,
        const Duration(minutes: 30),
        reason: "A's 10:00 used to be written onto B");
    expect(engine.seeks.last, const Duration(minutes: 30));
  });

  test('Play from start really starts at 0:00', () async {
    final engine = FakeEngine();
    final c = make(engine);
    seedPosition(ep('B'), const Duration(minutes: 30));

    await c.play(ep('B'), fromStart: true);
    await settle();

    expect(engine.seeks, isEmpty);
    expect(c.position.value, Duration.zero);
  });

  test('a finished episode restarts rather than resuming at the end',
      () async {
    final engine = FakeEngine();
    final c = make(engine);
    seedPosition(ep('B'), const Duration(minutes: 59, seconds: 50)); // ≥97%

    await c.play(ep('B'));
    await settle();

    expect(engine.seeks, isEmpty);
  });

  group('cold-start restore', () {
    test('playing an episode marks the podcast as the session to restore',
        () async {
      final engine = FakeEngine();
      final c = make(engine);
      await c.play(ep('B'));
      await settle();

      expect(LastPlaybackDomain.isPodcast, isTrue);
      expect(PodcastPrefs.lastEpisode?.id, 'B');
    });

    test('a music item hands the session back to music', () async {
      final engine = FakeEngine();
      make(engine);
      LastPlaybackDomain.set(podcast: true);

      engine.mediaItem.add(const MediaItem(id: 'song', title: 'A song'));
      await settle();

      expect(LastPlaybackDomain.isPodcast, isFalse);
      expect(engine.commands, contains('setSpeed'),
          reason: 'music must get the engine back at 1.0×');
    });

    test('on launch, the last episode comes back PAUSED at its position',
        () async {
      seedPosition(ep('B'), const Duration(minutes: 42));
      PodcastPrefs.lastEpisode = ep('B');
      LastPlaybackDomain.set(podcast: true);

      final engine = FakeEngine();
      final c = make(engine);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(engine.lastRestore, isNotNull,
          reason: 'restoreSession loads without playing');
      expect(engine.lastRestore!['positionMs'],
          const Duration(minutes: 42).inMilliseconds);
      expect(engine.commands, isNot(contains('setSourceNPlay')));
      expect(c.currentEpisode.value?.id, 'B');
      expect(c.position.value, const Duration(minutes: 42));
    });

    test('nothing is restored when music owned the last session', () async {
      PodcastPrefs.lastEpisode = ep('B');
      LastPlaybackDomain.set(podcast: false);

      final engine = FakeEngine();
      make(engine);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(engine.lastRestore, isNull);
    });

    test('dismissing the player forgets the podcast session', () async {
      final engine = FakeEngine();
      final c = make(engine);
      await c.play(ep('B'));
      await settle();

      await c.dismiss();

      expect(PodcastPrefs.lastEpisode, isNull);
      expect(LastPlaybackDomain.isPodcast, isFalse);
    });
  });
}
