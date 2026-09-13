// podcast/models/episode_progress.dart
//
// Where the listener is inside one episode. This is the record that makes
// podcasts feel like podcasts: an episode is a place you leave and come back
// to, not a track you replay from zero.
//
// Music has no equivalent concept (a song resumes from the start), which is
// why this is a podcast-only model in a podcast-only store rather than a
// column bolted onto the music history.

class EpisodeProgress {
  final String episodeId;

  /// Last known playhead.
  final Duration position;

  /// Episode length as known when the position was written. Zero until the
  /// player has learned the real duration from the stream.
  final Duration duration;

  /// Sticky: once an episode is finished (or explicitly marked played) it
  /// stays completed even if the listener scrubs back.
  final bool completed;

  final DateTime lastPlayedAt;

  /// How many times playback of this episode has been started.
  final int startCount;

  /// Total time actually listened, accumulated across sessions. A better
  /// engagement signal than "did they open it" — the recommender uses it to
  /// tell a real listen from an accidental tap.
  final Duration listened;

  const EpisodeProgress({
    required this.episodeId,
    required this.position,
    required this.duration,
    required this.lastPlayedAt,
    this.completed = false,
    this.startCount = 1,
    this.listened = Duration.zero,
  });

  /// Treated as finished at 97% — podcast outros/credits mean the last
  /// seconds are routinely skipped, and "98% listened" should not sit in
  /// Continue Listening forever.
  static const double completionThreshold = 0.97;

  /// Below this, a start reads as a sample rather than a real listen; the
  /// episode is not offered as "continue listening".
  static const double startedThreshold = 0.01;

  double get percent {
    if (completed) return 1.0;
    final total = duration.inMilliseconds;
    if (total <= 0) return 0.0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration get remaining {
    final left = duration - position;
    return left.isNegative ? Duration.zero : left;
  }

  /// Started, not finished, and far enough in to be worth resuming.
  bool get inProgress =>
      !completed && percent > startedThreshold && percent < completionThreshold;

  /// Started and then left well before the end — the abandonment signal the
  /// recommender demotes a show on.
  bool get abandoned =>
      !completed &&
      percent > startedThreshold &&
      percent < 0.25 &&
      DateTime.now().difference(lastPlayedAt).inDays >= 7;

  EpisodeProgress copyWith({
    Duration? position,
    Duration? duration,
    bool? completed,
    DateTime? lastPlayedAt,
    int? startCount,
    Duration? listened,
  }) =>
      EpisodeProgress(
        episodeId: episodeId,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        completed: completed ?? this.completed,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        startCount: startCount ?? this.startCount,
        listened: listened ?? this.listened,
      );

  Map<String, dynamic> toMap() => {
        'episodeId': episodeId,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'completed': completed,
        'lastPlayedMs': lastPlayedAt.millisecondsSinceEpoch,
        'startCount': startCount,
        'listenedMs': listened.inMilliseconds,
      };

  factory EpisodeProgress.fromMap(Map m) => EpisodeProgress(
        episodeId: (m['episodeId'] ?? '').toString(),
        position:
            Duration(milliseconds: (m['positionMs'] as num?)?.toInt() ?? 0),
        duration:
            Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
        completed: m['completed'] == true,
        lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['lastPlayedMs'] as num?)?.toInt() ?? 0),
        startCount: (m['startCount'] as num?)?.toInt() ?? 1,
        listened:
            Duration(milliseconds: (m['listenedMs'] as num?)?.toInt() ?? 0),
      );
}
