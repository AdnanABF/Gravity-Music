// podcast/models/podcast_episode.dart
//
// A single podcast EPISODE. Carries the show it belongs to (podcasts are
// always consumed in the context of a series), a real published date, a full
// description, and a chapter list that is empty today but modelled now so
// chapters can be filled in later without a rewrite (spec §13).
//
// [id] is a YouTube videoId, which is what makes shared playback possible: the
// app's existing stream resolver turns any videoId into an audio URL. That is
// the ONLY thing episodes borrow from the music side.

import 'package:audio_service/audio_service.dart';

import '../../shared/media_domain.dart';
import '../services/podcast_artwork.dart';

/// A named position inside an episode. Nothing populates this yet — YT Music's
/// podcast pages don't expose chapter markers — but episodes are parsed
/// through a constructor that accepts them, so a future source can fill them
/// in without touching call sites.
class PodcastChapter {
  final String title;
  final Duration start;

  const PodcastChapter({required this.title, required this.start});

  Map<String, dynamic> toMap() =>
      {'title': title, 'startMs': start.inMilliseconds};

  factory PodcastChapter.fromMap(Map m) => PodcastChapter(
        title: (m['title'] ?? '').toString(),
        start: Duration(milliseconds: (m['startMs'] as num?)?.toInt() ?? 0),
      );
}

class PodcastEpisode {
  /// YouTube videoId — the playback key.
  final String id;

  /// Episode detail page id (`MPED…`), for fetching the full description when
  /// the episode was discovered somewhere that only carried a summary.
  final String browseId;

  final String title;

  /// Owning show (`MPSPPL…`) and its display name. Both can be empty when an
  /// episode surfaced without its series attached; the UI falls back to the
  /// channel name.
  final String showId;
  final String showTitle;

  /// Episode art — frequently 16:9 (YouTube video frames), unlike album art.
  final String artwork;

  /// Show cover, kept alongside so a list can fall back to the series art when
  /// an episode has none of its own.
  final String showArtwork;

  final String description;

  /// Zero when the source didn't state one (search rows omit it). The player
  /// backfills the real duration from the audio stream once playing.
  final Duration duration;

  /// Best-effort absolute date parsed from labels like "3d ago" / "Aug 27".
  final DateTime? publishedAt;

  /// The raw label as YouTube rendered it, shown verbatim when we have it —
  /// "3d ago" reads better than a reconstructed date.
  final String publishedLabel;

  final List<PodcastChapter> chapters;

  const PodcastEpisode({
    required this.id,
    required this.title,
    this.browseId = '',
    this.showId = '',
    this.showTitle = '',
    this.artwork = '',
    this.showArtwork = '',
    this.description = '',
    this.duration = Duration.zero,
    this.publishedAt,
    this.publishedLabel = '',
    this.chapters = const [],
  });

  /// Art to show for this episode, preferring its own frame and falling back
  /// to the series cover.
  String get displayArtwork => artwork.isNotEmpty ? artwork : showArtwork;

  PodcastEpisode copyWith({
    String? browseId,
    String? title,
    String? showId,
    String? showTitle,
    String? artwork,
    String? showArtwork,
    String? description,
    Duration? duration,
    DateTime? publishedAt,
    String? publishedLabel,
    List<PodcastChapter>? chapters,
  }) =>
      PodcastEpisode(
        id: id,
        browseId: browseId ?? this.browseId,
        title: title ?? this.title,
        showId: showId ?? this.showId,
        showTitle: showTitle ?? this.showTitle,
        artwork: artwork ?? this.artwork,
        showArtwork: showArtwork ?? this.showArtwork,
        description: description ?? this.description,
        duration: duration ?? this.duration,
        publishedAt: publishedAt ?? this.publishedAt,
        publishedLabel: publishedLabel ?? this.publishedLabel,
        chapters: chapters ?? this.chapters,
      );

  /// Builds the MediaItem the shared audio handler plays.
  ///
  /// Two things matter here:
  ///  • `extras['url']` starts empty and is written back by the handler at
  ///    play time — the map must stay mutable (a const map would throw).
  ///  • the domain marker is what keeps music machinery off this item (see
  ///    shared/media_domain.dart).
  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        // Shown as the "artist" line on the lockscreen / notification, where
        // the series name is the useful thing to read.
        artist: showTitle,
        album: showTitle,
        // The permanent URL, not the signed one: the notification caches art
        // by URI, and a signed frame URL changes on every API response.
        artUri: displayArtwork.isEmpty
            ? null
            : Uri.tryParse(PodcastArtwork.canonical(displayArtwork)),
        duration: duration == Duration.zero ? null : duration,
        extras: {
          'url': '',
          kMediaDomainKey: kDomainPodcast,
          'showId': showId,
          'showTitle': showTitle,
          'showArtwork': showArtwork,
          'artwork': artwork,
          'browseId': browseId,
          'publishedLabel': publishedLabel,
        },
      );

  /// Rebuilds an episode from a MediaItem — used when the player is handed an
  /// item that came back from a restored session rather than from a screen.
  static PodcastEpisode? fromMediaItem(MediaItem? item) {
    if (!isPodcastItem(item)) return null;
    final e = item!.extras!;
    return PodcastEpisode(
      id: item.id,
      title: item.title,
      browseId: (e['browseId'] ?? '').toString(),
      showId: (e['showId'] ?? '').toString(),
      showTitle: (e['showTitle'] ?? item.artist ?? '').toString(),
      artwork: (e['artwork'] ?? '').toString(),
      showArtwork: (e['showArtwork'] ?? '').toString(),
      duration: item.duration ?? Duration.zero,
      publishedLabel: (e['publishedLabel'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'browseId': browseId,
        'title': title,
        'showId': showId,
        'showTitle': showTitle,
        'artwork': artwork,
        'showArtwork': showArtwork,
        'description': description,
        'durationMs': duration.inMilliseconds,
        'publishedMs': publishedAt?.millisecondsSinceEpoch,
        'publishedLabel': publishedLabel,
        if (chapters.isNotEmpty)
          'chapters': chapters.map((c) => c.toMap()).toList(),
      };

  factory PodcastEpisode.fromMap(Map m) => PodcastEpisode(
        id: (m['id'] ?? '').toString(),
        browseId: (m['browseId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        showId: (m['showId'] ?? '').toString(),
        showTitle: (m['showTitle'] ?? '').toString(),
        artwork: (m['artwork'] ?? '').toString(),
        showArtwork: (m['showArtwork'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        duration:
            Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
        publishedAt: m['publishedMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch((m['publishedMs'] as num).toInt())
            : null,
        publishedLabel: (m['publishedLabel'] ?? '').toString(),
        chapters: (m['chapters'] as List? ?? const [])
            .whereType<Map>()
            .map(PodcastChapter.fromMap)
            .toList(),
      );

  @override
  bool operator ==(Object other) => other is PodcastEpisode && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
