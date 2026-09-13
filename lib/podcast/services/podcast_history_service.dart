// podcast/services/podcast_history_service.dart
//
// Podcast listening history — a SEPARATE store from the music
// ListeningHistoryService, in a separate Hive box, with a different shape.
//
// Music history answers "how many times has this track been played". That
// question is meaningless for podcasts: nobody replays an episode 40 times,
// and the interesting signals are entirely different — did they FINISH it,
// how far did they get, how long did they actually listen, and which SHOW
// does the episode belong to.
//
// So this store keeps two kinds of record, both in box 'PodcastHistory':
//
//   'ep:<videoId>'   → { episode snapshot, EpisodeProgress }
//   'show:<showId>'  → { show snapshot, plays, completions, abandons,
//                        listenedMs, lastPlayedMs }
//
// Nothing here reads or writes 'ListeningHistory', and nothing in music reads
// this box — the two histories cannot see each other.

import 'package:hive/hive.dart';

import '../models/episode_progress.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';

/// One episode as it sits in history: what it is, plus where you are in it.
class PodcastHistoryEntry {
  final PodcastEpisode episode;
  final EpisodeProgress progress;

  const PodcastHistoryEntry({required this.episode, required this.progress});
}

/// Aggregate engagement with one show. The recommender's primary input.
class ShowAffinity {
  final PodcastShow show;

  /// Episodes of this show that have been started.
  final int plays;

  /// Episodes finished — the strongest positive signal.
  final int completions;

  /// Episodes started and left early — the negative one.
  final int abandons;

  /// Total listening time across the show.
  final Duration listened;

  final DateTime lastPlayedAt;

  const ShowAffinity({
    required this.show,
    required this.plays,
    required this.completions,
    required this.abandons,
    required this.listened,
    required this.lastPlayedAt,
  });

  /// Engagement score in roughly 0..1+. Completions dominate, raw starts
  /// count for little, abandonment subtracts, and everything decays with
  /// time since the last listen so a show dropped months ago stops crowding
  /// out current interests.
  double get score {
    final base = completions * 1.0 + plays * 0.25 - abandons * 0.5;
    final hours = listened.inMinutes / 60.0;
    final raw = base + hours * 0.15;
    final days = DateTime.now().difference(lastPlayedAt).inDays;
    final recency = days <= 7
        ? 1.0
        : (days <= 30 ? 0.75 : (days <= 90 ? 0.45 : 0.2));
    return raw <= 0 ? 0.0 : raw * recency;
  }
}

class PodcastHistoryService {
  static Box get _box => Hive.box('PodcastHistory');

  static const _epPrefix = 'ep:';
  static const _showPrefix = 'show:';

  // ── Episode progress ──────────────────────────────────────────────────────

  static String _epKey(String id) => '$_epPrefix$id';

  static EpisodeProgress? progressFor(String episodeId) {
    final raw = _box.get(_epKey(episodeId));
    if (raw is! Map) return null;
    final p = raw['progress'];
    if (p is! Map) return null;
    return EpisodeProgress.fromMap(p);
  }

  static PodcastEpisode? episodeFor(String episodeId) {
    final raw = _box.get(_epKey(episodeId));
    if (raw is! Map || raw['episode'] is! Map) return null;
    return PodcastEpisode.fromMap(raw['episode'] as Map);
  }

  /// Records that playback of [episode] has STARTED. Keeps any existing
  /// position (that's what makes resume work) and refreshes the stored
  /// snapshot so a renamed/re-arted episode updates in the UI.
  static void recordStart(PodcastEpisode episode) {
    if (episode.id.isEmpty) return;
    final existing = progressFor(episode.id);
    final now = DateTime.now();
    final progress = existing == null
        ? EpisodeProgress(
            episodeId: episode.id,
            position: Duration.zero,
            duration: episode.duration,
            lastPlayedAt: now,
          )
        : existing.copyWith(
            lastPlayedAt: now,
            startCount: existing.startCount + 1,
            duration: existing.duration > Duration.zero
                ? existing.duration
                : episode.duration,
          );
    _write(episode, progress);
    _touchShow(episode, startedNew: existing == null);
  }

  /// Persists the playhead. Called on a timer while playing and on every
  /// pause/stop/track-change, so a kill at any moment loses at most a few
  /// seconds.
  ///
  /// [listenedDelta] is real time spent listening since the last save, kept
  /// separate from [position] so scrubbing forward doesn't inflate it.
  static void saveProgress(
    PodcastEpisode episode, {
    required Duration position,
    Duration? duration,
    Duration listenedDelta = Duration.zero,
  }) {
    if (episode.id.isEmpty) return;
    final existing = progressFor(episode.id);
    final total = (duration != null && duration > Duration.zero)
        ? duration
        : (existing?.duration ?? episode.duration);

    var completed = existing?.completed ?? false;
    if (!completed &&
        total > Duration.zero &&
        position.inMilliseconds / total.inMilliseconds >=
            EpisodeProgress.completionThreshold) {
      completed = true;
    }

    final progress = EpisodeProgress(
      episodeId: episode.id,
      position: position,
      duration: total,
      completed: completed,
      lastPlayedAt: DateTime.now(),
      startCount: existing?.startCount ?? 1,
      listened: (existing?.listened ?? Duration.zero) + listenedDelta,
    );

    final wasCompleted = existing?.completed ?? false;
    _write(episode, progress);
    _touchShow(episode,
        listenedDelta: listenedDelta,
        completedNow: completed && !wasCompleted);
  }

  /// Explicit "mark as played" / "mark as unplayed" from the episode menu.
  static void setCompleted(PodcastEpisode episode, bool completed) {
    final existing = progressFor(episode.id);
    final total = existing?.duration ?? episode.duration;
    final progress = EpisodeProgress(
      episodeId: episode.id,
      position: completed ? total : Duration.zero,
      duration: total,
      completed: completed,
      lastPlayedAt: DateTime.now(),
      startCount: existing?.startCount ?? 1,
      listened: existing?.listened ?? Duration.zero,
    );
    final wasCompleted = existing?.completed ?? false;
    _write(episode, progress);
    if (completed && !wasCompleted) _touchShow(episode, completedNow: true);
  }

  /// Refreshes the stored episode METADATA (description, art, show) without
  /// touching its progress. Used by background hydration, which must never
  /// write a position: it runs while a resume may still be pending.
  static void updateSnapshot(PodcastEpisode episode) {
    final progress = progressFor(episode.id);
    if (progress == null) return; // not in history — nothing to update
    _write(episode, progress);
  }

  /// Forget one episode entirely (removes it from Continue Listening).
  static void forget(String episodeId) => _box.delete(_epKey(episodeId));

  static void _write(PodcastEpisode episode, EpisodeProgress progress) {
    // Merge onto the stored snapshot so a row parsed without a description
    // (search results) doesn't erase one captured from the show page.
    final stored = episodeFor(episode.id);
    final merged = stored == null
        ? episode
        : episode.copyWith(
            description: episode.description.isNotEmpty
                ? episode.description
                : stored.description,
            showId: episode.showId.isNotEmpty ? episode.showId : stored.showId,
            showTitle: episode.showTitle.isNotEmpty
                ? episode.showTitle
                : stored.showTitle,
            showArtwork: episode.showArtwork.isNotEmpty
                ? episode.showArtwork
                : stored.showArtwork,
            duration: episode.duration > Duration.zero
                ? episode.duration
                : stored.duration,
          );
    _box.put(_epKey(episode.id), {
      'episode': merged.toMap(),
      'progress': progress.toMap(),
    });
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  static List<PodcastHistoryEntry> _entries() {
    final out = <PodcastHistoryEntry>[];
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(_epPrefix)) continue;
      final raw = _box.get(key);
      if (raw is! Map || raw['episode'] is! Map || raw['progress'] is! Map) {
        continue;
      }
      final ep = PodcastEpisode.fromMap(raw['episode'] as Map);
      if (ep.id.isEmpty) continue;
      out.add(PodcastHistoryEntry(
        episode: ep,
        progress: EpisodeProgress.fromMap(raw['progress'] as Map),
      ));
    }
    return out;
  }

  static bool get hasHistory => _entries().isNotEmpty;

  /// Everything played, most recent first.
  static List<PodcastHistoryEntry> recent({int limit = 50}) {
    final list = _entries()
      ..sort((a, b) =>
          b.progress.lastPlayedAt.compareTo(a.progress.lastPlayedAt));
    return list.take(limit).toList();
  }

  /// Started, unfinished, most recent first — the Continue Listening row.
  static List<PodcastHistoryEntry> continueListening({int limit = 20}) =>
      recent(limit: 200)
          .where((e) => e.progress.inProgress)
          .take(limit)
          .toList();

  static List<PodcastHistoryEntry> completed({int limit = 50}) =>
      recent(limit: 300).where((e) => e.progress.completed).take(limit).toList();

  // ── Show aggregates ───────────────────────────────────────────────────────

  static String _showKey(String id) => '$_showPrefix$id';

  static void _touchShow(
    PodcastEpisode episode, {
    bool startedNew = false,
    bool completedNow = false,
    Duration listenedDelta = Duration.zero,
  }) {
    final showId = episode.showId;
    if (showId.isEmpty) return;
    final raw = _box.get(_showKey(showId));
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    m['showId'] = showId;
    m['title'] = episode.showTitle.isNotEmpty
        ? episode.showTitle
        : (m['title'] ?? '').toString();
    m['artwork'] = episode.showArtwork.isNotEmpty
        ? episode.showArtwork
        : (m['artwork'] ?? '').toString();
    m['plays'] = ((m['plays'] as num?)?.toInt() ?? 0) + (startedNew ? 1 : 0);
    m['completions'] =
        ((m['completions'] as num?)?.toInt() ?? 0) + (completedNow ? 1 : 0);
    m['listenedMs'] = ((m['listenedMs'] as num?)?.toInt() ?? 0) +
        listenedDelta.inMilliseconds;
    m['lastPlayedMs'] = DateTime.now().millisecondsSinceEpoch;
    _box.put(_showKey(showId), m);
  }

  /// Per-show engagement, strongest first. Abandonment is derived from the
  /// episode records rather than stored, so the threshold can change without a
  /// migration.
  static List<ShowAffinity> showAffinities() {
    final abandonsByShow = <String, int>{};
    for (final e in _entries()) {
      if (e.progress.abandoned && e.episode.showId.isNotEmpty) {
        abandonsByShow.update(e.episode.showId, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    final out = <ShowAffinity>[];
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(_showPrefix)) continue;
      final raw = _box.get(key);
      if (raw is! Map) continue;
      final id = (raw['showId'] ?? '').toString();
      if (id.isEmpty) continue;
      out.add(ShowAffinity(
        show: PodcastShow(
          id: id,
          title: (raw['title'] ?? '').toString(),
          artwork: (raw['artwork'] ?? '').toString(),
        ),
        plays: (raw['plays'] as num?)?.toInt() ?? 0,
        completions: (raw['completions'] as num?)?.toInt() ?? 0,
        abandons: abandonsByShow[id] ?? 0,
        listened:
            Duration(milliseconds: (raw['listenedMs'] as num?)?.toInt() ?? 0),
        lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(
            (raw['lastPlayedMs'] as num?)?.toInt() ?? 0),
      ));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Wipes podcast history only. Music history is in a different box and is
  /// not touched.
  static Future<void> clear() => _box.clear();
}
