// podcast/models/podcast_show.dart
//
// A podcast SHOW (series). Deliberately NOT modelled on SearchResult: a show
// has no videoId, no duration and no artist list — it has a browse id, a
// creator, a description and an episode feed. Forcing it into the music model
// would mean a videoId that never plays and an "artists" list of one.

class PodcastShow {
  /// YT Music show page id (`MPSPPL…`). Stable — used as the follow key and
  /// as the browse id for [PodcastService.showDetail].
  final String id;

  final String title;

  /// Creator / publisher ("The Diary Of A CEO", "Vox Media"…).
  final String author;

  /// Cover art. Usually square for shows, but never assumed to be — see
  /// PodcastArtwork, which preserves whatever ratio arrives.
  final String artwork;

  final String description;

  /// Creator's YouTube channel id (`UC…`), when the page exposed one. Used to
  /// group shows by creator for recommendations.
  final String channelId;

  /// The creator's channel avatar (`yt3.ggpht.com/…`) — "the YouTuber's
  /// picture". Only the show PAGE carries it (search rows don't).
  ///
  /// Worth keeping beyond looks: cover art is a SIGNED URL that expires, while
  /// ggpht avatars are unsigned and permanent, so the avatar is the fallback
  /// that still renders when a stored cover URL has gone dead.
  final String avatar;

  /// Topic/category label when the show was discovered through a topic shelf
  /// ("Meditation", "True crime"…). Empty when unknown. Drives topic affinity
  /// in the recommender.
  final String category;

  const PodcastShow({
    required this.id,
    required this.title,
    this.author = '',
    this.artwork = '',
    this.description = '',
    this.channelId = '',
    this.category = '',
    this.avatar = '',
  });

  /// Cover to show, falling back to the creator's avatar.
  String get displayArtwork => artwork.isNotEmpty ? artwork : avatar;

  PodcastShow copyWith({
    String? title,
    String? author,
    String? artwork,
    String? description,
    String? channelId,
    String? category,
    String? avatar,
  }) =>
      PodcastShow(
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        artwork: artwork ?? this.artwork,
        description: description ?? this.description,
        channelId: channelId ?? this.channelId,
        category: category ?? this.category,
        avatar: avatar ?? this.avatar,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'artwork': artwork,
        'description': description,
        'channelId': channelId,
        'category': category,
        'avatar': avatar,
      };

  factory PodcastShow.fromMap(Map m) => PodcastShow(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        author: (m['author'] ?? '').toString(),
        artwork: (m['artwork'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        channelId: (m['channelId'] ?? '').toString(),
        category: (m['category'] ?? '').toString(),
        avatar: (m['avatar'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) => other is PodcastShow && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
