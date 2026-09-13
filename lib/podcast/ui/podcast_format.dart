// podcast/ui/podcast_format.dart
//
// Podcast-shaped formatters. Music formats everything as m:ss because songs
// are minutes long; episodes are hours long and are talked about in words
// ("2 hr 16 min", "18 min left", "3d ago"), so they get their own set.

import '../models/episode_progress.dart';

/// "2 hr 16 min" / "45 min" / "38 sec" — how a length is *described*.
String fmtEpisodeLength(Duration d) {
  if (d <= Duration.zero) return '';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return m == 0 ? '$h hr' : '$h hr $m min';
  if (m > 0) return '$m min';
  return '${d.inSeconds} sec';
}

/// "18 min left" — what a partially-heard episode says.
String fmtRemaining(Duration d) {
  if (d <= Duration.zero) return 'Finished';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '$h hr $m min left';
  if (m > 0) return '$m min left';
  return '${d.inSeconds} sec left';
}

/// "27:34" / "1:27:34" — the clock, for the player's scrubber.
String fmtClock(Duration d) {
  final neg = d.isNegative;
  final abs = neg ? -d : d;
  final h = abs.inHours;
  final m = abs.inMinutes.remainder(60);
  final s = abs.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body =
      h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  return neg ? '-$body' : body;
}

/// The publish date, preferring YouTube's own wording and falling back to a
/// compact absolute date.
String fmtPublished(DateTime? at, String label) {
  if (label.isNotEmpty) return label;
  if (at == null) return '';
  final days = DateTime.now().difference(at).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  if (days < 365) return '${_month(at.month)} ${at.day}';
  return '${_month(at.month)} ${at.day}, ${at.year}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _month(int m) => _months[(m - 1).clamp(0, 11)];

/// The status line under an episode title: "Played", "18 min left" or the
/// episode length, joined to the publish date.
String episodeStatusLine(
  Duration length,
  EpisodeProgress? progress,
  DateTime? publishedAt,
  String publishedLabel,
) {
  final date = fmtPublished(publishedAt, publishedLabel);
  final String state;
  if (progress != null && progress.completed) {
    state = 'Played';
  } else if (progress != null && progress.inProgress) {
    state = fmtRemaining(progress.remaining);
  } else {
    state = fmtEpisodeLength(length);
  }
  if (date.isEmpty) return state;
  if (state.isEmpty) return date;
  return '$date · $state';
}

/// Collapses a description to a single readable line for list rows.
String oneLine(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();
