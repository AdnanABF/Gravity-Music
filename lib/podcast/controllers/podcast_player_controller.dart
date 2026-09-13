// podcast/controllers/podcast_player_controller.dart
//
// Podcast playback. Talks to the SHARED audio handler — there is exactly one
// per app, and it owns the media notification, the lockscreen/MPRIS contract
// and (on Android) the foreground service that keeps audio alive in the
// background. A second player would have none of that, so episodes would stop
// the moment the screen locked.
//
// Everything ABOVE that shared engine is podcast-specific and lives here:
//
//   • resume — every episode remembers its playhead, forever, across restarts
//   • ±15s / ±30s skips instead of prev/next as the primary transport
//   • a remembered playback speed that is INDEPENDENT of music: the engine is
//     reset to 1.0× whenever a non-podcast item becomes current, so a 1.5×
//     episode can never leave the next song playing fast
//   • progress written to the podcast history store, never to music history
//
// This controller never touches PlayerController, LibraryService,
// ListeningHistoryService or any other music state.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '../../shared/media_domain.dart';
import '../models/episode_progress.dart';
import '../models/podcast_episode.dart';
import '../services/podcast_history_service.dart';
import '../services/podcast_service.dart';
import '../services/podcast_prefs.dart';

class PodcastPlayerController extends GetxController {
  PodcastPlayerController({
    required this.audioHandler,
    this.observeEngine = true,
    Stream<Duration>? positionStream,
  }) : _positionStream = positionStream;

  /// Playhead ticks. `AudioService.position` in the app; tests inject their
  /// own, since that stream needs a live platform handler.
  final Stream<Duration>? _positionStream;

  final AudioHandler audioHandler;

  /// Whether to subscribe to the shared engine's streams. Always true in the
  /// app. Widget tests turn it off: `AudioService.position` reaches for the
  /// platform handler, which doesn't exist under the test binding.
  final bool observeEngine;

  /// The episode currently loaded in the shared engine, or null when the
  /// engine is playing music (or nothing).
  final currentEpisode = Rxn<PodcastEpisode>();

  final isPlaying = false.obs;
  final isLoading = false.obs;
  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;

  /// Remembered podcast speed, restored at startup.
  final speed = 1.0.obs;

  final skipBackSeconds = 15.obs;
  final skipForwardSeconds = 30.obs;

  /// Bumped after any progress write so lists can rebuild their bars without
  /// each row subscribing to the position stream.
  final progressRevision = 0.obs;

  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<Duration>? _posSub;

  /// Throttles the progress write to disk (~every 5s of playback).
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  static const _saveEvery = Duration(seconds: 5);

  /// Previous position tick, used to accumulate REAL listening time. A jump
  /// larger than [_maxTickGap] is a seek, not listening, and is not counted.
  Duration? _lastTick;
  Duration _pendingListened = Duration.zero;
  static const _maxTickGap = Duration(seconds: 4);

  /// The episode that [position] currently BELONGS to — the only episode a
  /// progress write may ever target.
  ///
  /// Deliberately separate from [currentEpisode]. The UI flips
  /// [currentEpisode] the instant the user taps, but the engine is still on
  /// the previous source for a moment, and position ticks keep describing
  /// THAT source. Writing progress against [currentEpisode] is exactly what
  /// used to overwrite a resume point: the old episode's playhead (and then a
  /// zero from the loading state) landed on the episode being resumed.
  PodcastEpisode? _tracked;

  /// Set from the moment an episode is requested until its source is ready and
  /// the saved position has been applied. While set, NOTHING is persisted for
  /// it: the engine reports 0:00 while it loads, and saving that would erase
  /// the very position we are about to seek to.
  ({String id, Duration at})? _pendingResume;

  @override
  void onInit() {
    super.onInit();
    speed.value = PodcastPrefs.speed;
    skipBackSeconds.value = PodcastPrefs.skipBackSeconds;
    skipForwardSeconds.value = PodcastPrefs.skipForwardSeconds;

    if (!observeEngine) return;
    _itemSub = audioHandler.mediaItem.listen(_onItemChanged);
    _stateSub = audioHandler.playbackState.listen(_onState);
    _posSub = (_positionStream ?? AudioService.position).listen(_onPosition);

    // Bring back the episode the app was closed on. Runs alongside music's own
    // restore, which stands down when the last session was a podcast (see
    // LastPlaybackDomain) — so exactly one of the two restores ever runs.
    if (LastPlaybackDomain.isPodcast) {
      Future.delayed(const Duration(milliseconds: 500), _restoreSession);
    }
  }

  @override
  void onClose() {
    _flush();
    _itemSub?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    super.onClose();
  }

  // ── Engine observation ────────────────────────────────────────────────────

  void _onItemChanged(MediaItem? item) {
    // Stream events arrive asynchronously, so one can describe a state the
    // engine has already left — most commonly the subject REPLAYING its old
    // value (often null) to a fresh subscriber, landing after play() has
    // started. Acting on that stale null used to cancel the pending resume.
    // Only the item the engine holds right now is authoritative.
    if (item?.id != audioHandler.mediaItem.value?.id) return;

    final episode = PodcastEpisode.fromMediaItem(item);

    // Our own request arriving at the engine. [play] has already persisted
    // the previous episode and set up the pending resume — don't flush again,
    // and don't reset the position the UI is showing.
    if (episode != null && episode.id == _pendingResume?.id) {
      if (item?.duration != null && item!.duration! > Duration.zero) {
        duration.value = item.duration!;
      }
      return;
    }

    // The engine moved on by itself (music started, player dismissed, or an
    // unexpected item). Persist the episode we were tracking first.
    _flush();
    _tracked = null;
    _pendingResume = null;
    _lastTick = null;
    _pendingListened = Duration.zero;

    currentEpisode.value = episode;

    if (episode == null) {
      if (item != null) {
        // Music is current. Hand the engine back at normal speed — this is
        // what keeps podcast speed from leaking into Music Mode — and record
        // that music owns the session now, so a cold start restores music.
        _applySpeed(1.0);
        LastPlaybackDomain.set(podcast: false);
      }
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isLoading.value = false;
      return;
    }

    // A podcast item we didn't request (defensive; nothing does this today).
    _tracked = episode;
    duration.value = item?.duration ?? episode.duration;
    position.value = Duration.zero;
    _applySpeed(speed.value);
  }

  void _onState(PlaybackState s) {
    final loading = s.processingState == AudioProcessingState.loading ||
        s.processingState == AudioProcessingState.buffering;
    final playing = s.playing && !loading;

    // The requested episode could not be loaded (removed video, offline).
    // Drop the pending resume so the spinner stops — and without having
    // persisted anything, so its saved position survives for a retry.
    if (_pendingResume != null &&
        s.processingState == AudioProcessingState.error) {
      _pendingResume = null;
      isLoading.value = false;
      isPlaying.value = false;
      return;
    }

    // Apply a pending resume once the requested source is actually loaded.
    final pending = _pendingResume;
    if (pending != null &&
        s.processingState == AudioProcessingState.ready &&
        audioHandler.mediaItem.value?.id == pending.id) {
      _completeResume(pending);
    }

    isLoading.value = loading || _pendingResume != null;
    if (isPlaying.value && !playing) _flush(); // pause/stop → persist now
    isPlaying.value = playing;
  }

  /// Seeks the freshly loaded source to the saved position and only THEN
  /// starts tracking it — so the first progress write can never be a 0:00
  /// from the load.
  Future<void> _completeResume(({String id, Duration at}) pending) async {
    _pendingResume = null;
    final episode = currentEpisode.value;
    if (episode == null || episode.id != pending.id) return;

    if (pending.at > const Duration(seconds: 3)) {
      await audioHandler.seek(pending.at);
    }
    position.value = pending.at;
    _lastTick = pending.at;
    _pendingListened = Duration.zero;
    _tracked = episode;
    isLoading.value = false;
    _applySpeed(speed.value);
  }

  void _onPosition(Duration pos) {
    final episode = _tracked;
    // Nothing to track, or still loading: keep showing the resume point
    // rather than the 0:00 the engine reports mid-load.
    if (episode == null || _pendingResume != null) return;
    if (currentEpisode.value?.id != episode.id) return;

    position.value = pos;

    // Accumulate genuine listening time: only forward movement small enough
    // to be playback rather than a seek.
    final prev = _lastTick;
    if (prev != null && isPlaying.value) {
      final delta = pos - prev;
      if (delta > Duration.zero && delta <= _maxTickGap) {
        _pendingListened += delta;
      }
    }
    _lastTick = pos;

    if (!isPlaying.value) return;
    if (DateTime.now().difference(_lastSave) < _saveEvery) return;
    _flush();
  }

  /// Writes the tracked episode's playhead to the podcast history store.
  void _flush() {
    final episode = _tracked;
    if (episode == null || _pendingResume != null) return;
    if (position.value <= Duration.zero && _pendingListened == Duration.zero) {
      return;
    }
    PodcastHistoryService.saveProgress(
      episode,
      position: position.value,
      duration: duration.value > Duration.zero ? duration.value : null,
      listenedDelta: _pendingListened,
    );
    _pendingListened = Duration.zero;
    _lastSave = DateTime.now();
    progressRevision.value++;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  /// Where [episode] should start: its saved position, unless it was finished
  /// (resuming to the last second of something already heard is never what's
  /// wanted) or the caller asked for the start.
  Duration _resumePointFor(PodcastEpisode episode, {bool fromStart = false}) {
    if (fromStart) return Duration.zero;
    final saved = PodcastHistoryService.progressFor(episode.id);
    if (saved == null || saved.completed) return Duration.zero;
    return saved.position;
  }

  /// Plays [episode], resuming from its saved position unless [fromStart].
  Future<void> play(PodcastEpisode episode, {bool fromStart = false}) async {
    if (episode.id.isEmpty) return;

    // Already loaded: this is a resume of the live source, not a reload.
    if (!fromStart &&
        currentEpisode.value?.id == episode.id &&
        _pendingResume == null) {
      await audioHandler.play();
      return;
    }

    // 1. Persist where the PREVIOUS episode got to, while it is still the
    //    tracked one. After this line nothing may write to it.
    _flush();
    _tracked = null;
    _lastTick = null;
    _pendingListened = Duration.zero;

    // 2. Read the resume point BEFORE recordStart touches the record.
    final resumeAt = _resumePointFor(episode, fromStart: fromStart);
    PodcastHistoryService.recordStart(episode);
    if (fromStart) {
      PodcastHistoryService.saveProgress(episode, position: Duration.zero);
    }

    final saved = PodcastHistoryService.progressFor(episode.id);
    _pendingResume = (id: episode.id, at: resumeAt);
    currentEpisode.value = episode;
    position.value = resumeAt; // the UI shows the resume point immediately
    duration.value = episode.duration > Duration.zero
        ? episode.duration
        : (saved?.duration ?? Duration.zero);
    isLoading.value = true;

    _rememberSession(episode);

    // NOT awaited. just_audio's play() future completes only when playback
    // PAUSES or ENDS, and setSourceNPlay awaits it — so awaiting here used to
    // park this method for the whole episode, and the resume seek below it
    // only ever ran when the user hit pause. That was "resume starts over".
    // The seek now happens in _onState, the moment the source is ready.
    unawaited(audioHandler
        .customAction('setSourceNPlay', {'mediaItem': episode.toMediaItem()}));

    _hydrate(episode);
  }

  /// Restores the episode the app was closed on: loaded and positioned, but
  /// paused — the same courtesy music's session restore gives.
  Future<void> _restoreSession() async {
    final episode = PodcastPrefs.lastEpisode;
    if (episode == null || audioHandler.mediaItem.value != null) return;

    final resumeAt = _resumePointFor(episode);
    _pendingResume = (id: episode.id, at: resumeAt);
    currentEpisode.value = episode;
    position.value = resumeAt;
    duration.value = PodcastHistoryService.progressFor(episode.id)?.duration ??
        episode.duration;
    isLoading.value = true;

    // restoreSession loads WITHOUT playing and seeks to positionMs itself.
    await audioHandler.customAction('restoreSession', {
      'items': [episode.toMediaItem()],
      'index': 0,
      'positionMs': resumeAt.inMilliseconds,
      'userQueue': const <String>[],
    });
    // If the source could not be resolved (offline, removed video) the ready
    // state never arrives; stop showing a spinner forever.
    if (_pendingResume?.id == episode.id) {
      final ready = audioHandler.playbackState.value.processingState ==
          AudioProcessingState.ready;
      if (ready) {
        await _completeResume(_pendingResume!);
      } else {
        _pendingResume = null;
        _tracked = episode;
        isLoading.value = false;
      }
    }
    _hydrate(episode);
  }

  /// Marks this episode as the session to restore on the next cold start.
  void _rememberSession(PodcastEpisode episode) {
    PodcastPrefs.lastEpisode = episode;
    LastPlaybackDomain.set(podcast: true);
  }

  /// Fills in the episode notes (and a missing duration) in the background.
  ///
  /// Episodes reached from search rows, Continue Listening or a download carry
  /// no description — YouTube only returns one on the show page or the
  /// episode's own page — so the player screen would show a title and nothing
  /// else. This backfills after playback has already started, so it never
  /// delays audio.
  Future<void> _hydrate(PodcastEpisode episode) async {
    if (episode.description.isNotEmpty) return;
    final full = await PodcastService.hydrate(episode);
    // The listener may have moved on while the request was in flight.
    if (full.description.isEmpty || currentEpisode.value?.id != episode.id) {
      return;
    }
    currentEpisode.value = full;
    if (_tracked?.id == full.id) _tracked = full;
    // Snapshot only — never a position write, which could race the resume.
    PodcastHistoryService.updateSnapshot(full);
    if (PodcastPrefs.lastEpisode?.id == full.id) PodcastPrefs.lastEpisode = full;
    progressRevision.value++;
  }

  /// Resume from wherever the listener left off (Continue Listening tiles).
  Future<void> resume(PodcastEpisode episode) => play(episode);

  Future<void> togglePlayPause() async {
    if (isPlaying.value) {
      await audioHandler.pause();
      _flush();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> pause() async {
    await audioHandler.pause();
    _flush();
  }

  Future<void> seek(Duration to) async {
    // A seek during load would be overwritten by the pending resume anyway.
    if (_pendingResume != null) return;
    final total = duration.value;
    var target = to;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await audioHandler.seek(target);
    position.value = target;
    _lastTick = target; // a seek is not listening time
    _flush();
  }

  /// The podcast transport: jump back a short way (missed a sentence)…
  Future<void> skipBack() =>
      seek(position.value - Duration(seconds: skipBackSeconds.value));

  /// …and forward a longer way (skipping an ad read).
  Future<void> skipForward() =>
      seek(position.value + Duration(seconds: skipForwardSeconds.value));

  /// Closes the podcast player: stops audio and clears the episode, so the
  /// podcast mini-player disappears.
  Future<void> dismiss() async {
    _flush();
    _tracked = null;
    _pendingResume = null;
    currentEpisode.value = null;
    // The user closed the player: nothing to bring back on the next launch.
    PodcastPrefs.lastEpisode = null;
    LastPlaybackDomain.set(podcast: false);
    await audioHandler.customAction('dismissPlayer');
  }

  // ── Speed ─────────────────────────────────────────────────────────────────

  void setSpeed(double value) {
    speed.value = value;
    PodcastPrefs.speed = value;
    // Only push to the engine while a podcast is actually current — otherwise
    // changing the podcast speed from a settings sheet would alter music.
    if (currentEpisode.value != null) _applySpeed(value);
  }

  void cycleSpeed() {
    const options = PodcastPrefs.speeds;
    final i = options.indexOf(speed.value);
    setSpeed(options[(i < 0 ? 1 : i + 1) % options.length]);
  }

  void _applySpeed(double value) =>
      audioHandler.customAction('setSpeed', {'value': value});

  // ── Skip interval preferences ─────────────────────────────────────────────

  void setSkipBack(int seconds) {
    skipBackSeconds.value = seconds;
    PodcastPrefs.skipBackSeconds = seconds;
  }

  void setSkipForward(int seconds) {
    skipForwardSeconds.value = seconds;
    PodcastPrefs.skipForwardSeconds = seconds;
  }

  // ── Marking played ────────────────────────────────────────────────────────

  void markPlayed(PodcastEpisode episode, {bool played = true}) {
    PodcastHistoryService.setCompleted(episode, played);
    progressRevision.value++;
  }

  /// Saved progress for [episodeId], for rendering a row's progress bar.
  EpisodeProgress? progressFor(String episodeId) =>
      PodcastHistoryService.progressFor(episodeId);

  /// True when [episodeId] is the episode currently loaded in the engine.
  bool isCurrent(String episodeId) => currentEpisode.value?.id == episodeId;
}

/// Convenience for widgets: the podcast player, or null before registration.
PodcastPlayerController? get podcastPlayerOrNull =>
    Get.isRegistered<PodcastPlayerController>()
        ? Get.find<PodcastPlayerController>()
        : null;

/// True when the shared engine is currently on a podcast episode. Used by the
/// shell to decide which mini-player to show, so Music Mode never renders an
/// episode through the music mini-player.
bool get engineIsOnPodcast =>
    podcastPlayerOrNull?.currentEpisode.value != null;

/// Re-exported so shell code can check an item without importing the marker.
bool mediaItemIsPodcast(MediaItem? item) => isPodcastItem(item);
