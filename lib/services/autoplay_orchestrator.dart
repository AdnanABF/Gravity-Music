// services/autoplay_orchestrator.dart
//
// Watermark-driven queue refill. Subscribes to queue + playback streams,
// computes "remaining tracks after the current one", and when that falls
// below the watermark, fetches more recommendations and appends them.
//
// The watermark is what differentiates this from naive autoplay. With a
// reactive ("queue ended → fetch next") model, the user hears a 1–3s gap
// while the rec server responds. With a predictive ("3 tracks left →
// start fetching now") model, by the time the user gets there, recs have
// already landed and playback continues seamlessly.

import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../shared/media_domain.dart';
import 'recommendation_service.dart';

class AutoplayOrchestrator {
  AutoplayOrchestrator({
    required this.audioHandler,
    required this.onTracksReady,
    this.watermark = 3,
  });

  final AudioHandler audioHandler;

  /// Called with new tracks to append to the queue. The caller is
  /// expected to route these through the same `addQueueItem` path the
  /// rest of the app uses, so QueueManager bookkeeping stays in sync.
  final Future<void> Function(List<RecommendedTrack> tracks) onTracksReady;

  /// Fire a fetch when remaining tracks after current drops below this.
  /// 3 gives ~10 minutes of buffer at typical song length — enough headroom
  /// even for the Render.com cold-start case.
  final int watermark;

  // De-dup. The same seed always returns the same recs (within the
  // service's TTL), so we don't refetch from the same id repeatedly.
  String? _lastSeedVideoId;

  // Single-flight guard. Each watermark dip schedules at most one fetch.
  bool _fetchInFlight = false;

  // Subscriptions, retained so we can cancel on stop().
  StreamSubscription<List<MediaItem>>? _queueSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  /// Begin observing. Safe to call once per controller lifetime.
  void start() {
    _queueSub = audioHandler.queue.listen((_) => _check());
    _playbackSub = audioHandler.playbackState.listen((_) => _check());
  }

  /// Stop observing. Idempotent.
  void stop() {
    _queueSub?.cancel();
    _queueSub = null;
    _playbackSub?.cancel();
    _playbackSub = null;
  }

  void _check() {
    if (_fetchInFlight) return;

    final items = audioHandler.queue.value;
    final currentIdx = audioHandler.playbackState.value.queueIndex;
    if (items.isEmpty || currentIdx == null) return;

    // Podcast Mode plays through the same handler (there is only one, and it
    // owns the notification + Android foreground service). Without this
    // guard, a single-episode queue reads as "0 tracks remaining" and this
    // orchestrator would seed YouTube music radio from the EPISODE's videoId
    // and append songs behind it. Music items never carry the marker, so this
    // is a no-op for every music queue.
    if (currentIdx >= 0 &&
        currentIdx < items.length &&
        isPodcastItem(items[currentIdx])) {
      return;
    }
    if (isPodcastItem(items.last)) return;

    final remaining = items.length - currentIdx - 1;
    if (remaining >= watermark) return;

    // Seed from the LAST song in the queue, not the currently playing one.
    // This way each top-up expands the musical neighborhood rather than
    // repeatedly fetching from the same source song.
    final seed = items.last.id;
    if (seed.isEmpty) return;
    if (seed == _lastSeedVideoId) return; // already exhausted this seed

    // Fire-and-forget; _fetchInFlight covers reentrancy.
    _fire(seed);
  }

  Future<void> _fire(String seedVideoId) async {
    _fetchInFlight = true;
    _lastSeedVideoId = seedVideoId;
    try {
      final recs = await RecommendationService.getRecommendations(seedVideoId);
      // Drop anything already in the queue. The rec service can return
      // overlapping suggestions across nearby seed videos.
      final queueIds = audioHandler.queue.value.map((m) => m.id).toSet();
      final fresh = recs.where((r) => !queueIds.contains(r.videoId)).toList();
      if (fresh.isEmpty) return;
      await onTracksReady(fresh);
    } catch (_) {
      // Network failure or similar — bail silently. The next watermark
      // dip (after the user advances or recs are added elsewhere) will
      // retry, with a fresh seed if available.
    } finally {
      _fetchInFlight = false;
    }
  }
}
