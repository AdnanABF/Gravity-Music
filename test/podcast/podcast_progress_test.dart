// Persistent episode progress and the podcast-only history store — the two
// things that make an episode a place you return to rather than a track you
// replay. Also pins that the podcast history lives in its OWN Hive box, so
// music's 'ListeningHistory' can never see an episode.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:saragama/podcast/models/episode_progress.dart';
import 'package:saragama/podcast/models/podcast_episode.dart';
import 'package:saragama/podcast/services/podcast_history_service.dart';
import 'package:saragama/podcast/services/podcast_library_service.dart';
import 'package:saragama/podcast/models/podcast_show.dart';

const _episode = PodcastEpisode(
  id: 'ep1',
  title: 'How X Changed Everything',
  showId: 'show1',
  showTitle: 'The Diary Of A CEO',
  duration: Duration(minutes: 58, seconds: 21),
);

EpisodeProgress _p({
  required Duration position,
  Duration duration = const Duration(minutes: 58, seconds: 21),
  bool completed = false,
  DateTime? at,
}) =>
    EpisodeProgress(
      episodeId: 'ep1',
      position: position,
      duration: duration,
      completed: completed,
      lastPlayedAt: at ?? DateTime.now(),
    );

void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('gm_podcast_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    for (final name in ['PodcastHistory', 'PodcastBox', 'ListeningHistory']) {
      if (!Hive.isBoxOpen(name)) await Hive.openBox(name);
      await Hive.box(name).clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  group('EpisodeProgress', () {
    test('percent and remaining', () {
      final p = _p(position: const Duration(minutes: 27, seconds: 34));
      expect(p.percent, closeTo(0.4724, 0.001));
      expect(p.remaining, const Duration(minutes: 30, seconds: 47));
    });

    test('a barely-touched episode is not "in progress"', () {
      // A mis-tap must not fill Continue Listening with things nobody played.
      expect(_p(position: const Duration(seconds: 5)).inProgress, isFalse);
    });

    test('past 97% counts as finished — outros are routinely skipped', () {
      final p = _p(position: const Duration(minutes: 57));
      expect(p.percent, greaterThan(EpisodeProgress.completionThreshold));
      expect(p.inProgress, isFalse);
    });

    test('completed is sticky and reports 100% even if scrubbed back', () {
      final p = _p(position: const Duration(minutes: 2), completed: true);
      expect(p.percent, 1.0);
      expect(p.inProgress, isFalse);
    });

    test('zero duration never divides by zero', () {
      expect(_p(position: Duration.zero, duration: Duration.zero).percent, 0.0);
      expect(_p(position: const Duration(minutes: 5), duration: Duration.zero)
          .remaining,
          Duration.zero);
    });

    test('abandonment needs BOTH an early stop and time passing', () {
      final justNow = _p(position: const Duration(minutes: 5));
      expect(justNow.abandoned, isFalse, reason: 'still mid-listen today');

      final stale = _p(
          position: const Duration(minutes: 5),
          at: DateTime.now().subtract(const Duration(days: 30)));
      expect(stale.abandoned, isTrue);
    });

    test('survives a Hive round-trip', () {
      final p = _p(position: const Duration(minutes: 12));
      final back = EpisodeProgress.fromMap(p.toMap());
      expect(back.position, p.position);
      expect(back.duration, p.duration);
      expect(back.completed, p.completed);
      expect(back.episodeId, p.episodeId);
    });
  });

  group('PodcastHistoryService', () {
    test('a position written now is readable after a "restart"', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 27, seconds: 34));

      final resumed = PodcastHistoryService.progressFor('ep1');
      expect(resumed, isNotNull);
      expect(resumed!.position, const Duration(minutes: 27, seconds: 34));
      expect(resumed.inProgress, isTrue);
    });

    test('starting again keeps the position — that IS resume', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 20));
      PodcastHistoryService.recordStart(_episode);

      expect(PodcastHistoryService.progressFor('ep1')!.position,
          const Duration(minutes: 20));
      expect(PodcastHistoryService.progressFor('ep1')!.startCount, 2);
    });

    test('crossing the threshold marks it completed for good', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 57, seconds: 30));
      expect(PodcastHistoryService.progressFor('ep1')!.completed, isTrue);

      // Scrubbing back later must not un-finish it.
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 3));
      expect(PodcastHistoryService.progressFor('ep1')!.completed, isTrue);
    });

    test('continueListening holds only started-but-unfinished episodes', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 20));

      const other = PodcastEpisode(
          id: 'ep2',
          title: 'Finished one',
          showId: 'show1',
          duration: Duration(minutes: 30));
      PodcastHistoryService.recordStart(other);
      PodcastHistoryService.saveProgress(other,
          position: const Duration(minutes: 30));

      final ids = PodcastHistoryService.continueListening()
          .map((e) => e.episode.id)
          .toList();
      expect(ids, ['ep1']);
    });

    test('listened time accumulates but scrubbing does not inflate it', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 5),
          listenedDelta: const Duration(minutes: 5));
      // A seek far forward reports a big position but no listening time.
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 40));

      expect(PodcastHistoryService.progressFor('ep1')!.listened,
          const Duration(minutes: 5));
    });

    test('show affinity ranks completion above raw starts', () {
      // show1: one completion. show2: two starts, no completion.
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 58));

      for (final id in ['a', 'b']) {
        final e = PodcastEpisode(
            id: id,
            title: id,
            showId: 'show2',
            showTitle: 'Other',
            duration: const Duration(minutes: 60));
        PodcastHistoryService.recordStart(e);
        PodcastHistoryService.saveProgress(e,
            position: const Duration(minutes: 2));
      }

      final ranked = PodcastHistoryService.showAffinities();
      expect(ranked.first.show.id, 'show1');
      expect(ranked.first.completions, 1);
    });

    test('NOTHING is written to the music history box', () {
      PodcastHistoryService.recordStart(_episode);
      PodcastHistoryService.saveProgress(_episode,
          position: const Duration(minutes: 27));
      PodcastLibraryService.follow(
          const PodcastShow(id: 'show1', title: 'The Diary Of A CEO'));

      // The taste profile behind "Made For You" reads this box. An episode in
      // it would put a podcast host in the user's artist affinities.
      expect(Hive.box('ListeningHistory').length, 0);
    });
  });

  group('PodcastLibraryService', () {
    test('follow / unfollow, most recent first', () {
      const a = PodcastShow(id: 's1', title: 'A');
      const b = PodcastShow(id: 's2', title: 'B');

      PodcastLibraryService.follow(a);
      PodcastLibraryService.follow(b);
      expect(PodcastLibraryService.following().map((s) => s.id), ['s2', 's1']);
      expect(PodcastLibraryService.isFollowing('s1'), isTrue);

      expect(PodcastLibraryService.toggleFollow(a), isFalse); // now unfollowed
      expect(PodcastLibraryService.isFollowing('s1'), isFalse);
      expect(PodcastLibraryService.following().map((s) => s.id), ['s2']);
    });

    test('a fresh show page repairs a follow whose cover went dead', () {
      // Followed long ago: its signed cover URL has since expired.
      PodcastLibraryService.follow(const PodcastShow(
          id: 's1', title: 'Figuring Out', artwork: 'https://dead.test/old'));
      PodcastLibraryService.follow(const PodcastShow(id: 's2', title: 'Other'));

      PodcastLibraryService.refreshMetadata(const PodcastShow(
        id: 's1',
        title: 'Figuring Out',
        artwork: 'https://i.ytimg.com/pl_c/X/studio_square_thumbnail.jpg?rs=new',
        avatar: 'https://yt3.ggpht.com/raj=s96',
        author: '', // empty fields must not wipe stored ones
      ));

      final list = PodcastLibraryService.following();
      expect(list.map((s) => s.id), ['s2', 's1'],
          reason: 'repaired in place — not re-followed to the top');
      final s1 = list.last;
      expect(s1.artwork, contains('rs=new'));
      expect(s1.avatar, 'https://yt3.ggpht.com/raj=s96');
    });

    test('refreshMetadata never follows a show on its own', () {
      PodcastLibraryService.refreshMetadata(
          const PodcastShow(id: 'nope', title: 'Not followed'));
      expect(PodcastLibraryService.isFollowing('nope'), isFalse);
    });

    test('follows without an avatar are queued for a refresh', () {
      PodcastLibraryService.follow(const PodcastShow(id: 's1', title: 'A'));
      expect(PodcastLibraryService.followsNeedingRefresh().map((s) => s.id),
          contains('s1'));

      PodcastLibraryService.refreshMetadata(const PodcastShow(
          id: 's1', title: 'A', avatar: 'https://yt3.ggpht.com/a=s96'));
      expect(PodcastLibraryService.followsNeedingRefresh(), isEmpty,
          reason: 'just refreshed, and now has an avatar');
    });

    test('following the same show twice does not duplicate it', () {
      const a = PodcastShow(id: 's1', title: 'A');
      PodcastLibraryService.follow(a);
      PodcastLibraryService.follow(a.copyWith(title: 'A (renamed)'));
      final list = PodcastLibraryService.following();
      expect(list.length, 1);
      expect(list.first.title, 'A (renamed)'); // metadata refreshed in place
    });
  });
}
