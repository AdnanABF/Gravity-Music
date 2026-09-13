// podcast/services/podcast_service.dart
//
// The podcast domain's read layer: show pages and the Discover feed, wrapped
// in a cache so a followed show opens instantly and works offline.
//
// Caching is STALE-WHILE-REVALIDATE: anything cached is returned immediately,
// whatever its age, and a stale entry is refreshed in the background. The
// first build blocked on the network whenever an entry passed its TTL, so a
// cold start the next day showed spinners over content already on disk — and
// an in-memory memo, once filled, was never refreshed at all, so new episodes
// didn't appear until the app restarted.
//
// Sits over YtPodcastApi the way AlbumService sits over YtMusicService — same
// shape, entirely separate code path. Nothing here can be reached from music.

import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'podcast_cache.dart';
import 'podcast_library_service.dart';
import 'yt_podcast_api.dart';

class PodcastService {
  static String _showKey(String id) => 'show:$id';
  static const _discoverKey = 'discover';
  static bool _discoverRefreshing = false;

  /// In-memory memo on top of the disk cache, so scrolling back to a show
  /// within one session doesn't even decode JSON.
  static final _memo = <String, PodcastShowDetail>{};

  /// Show ids with a background refresh already running (single-flight).
  static final _revalidating = <String>{};

  /// Fires with the fresh page after a background refresh, so an open screen
  /// can swap in new episodes without being re-opened.
  static final List<void Function(PodcastShowDetail)> _showListeners = [];
  static void addShowListener(void Function(PodcastShowDetail) fn) =>
      _showListeners.add(fn);
  static void removeShowListener(void Function(PodcastShowDetail) fn) =>
      _showListeners.remove(fn);

  /// A show page. Cached content comes back at once — stale content too, with
  /// a refresh kicked off behind it. Only a show never seen before waits on
  /// the network. [forceRefresh] (pull-to-refresh) always waits.
  static Future<PodcastShowDetail?> showDetail(String showId,
      {bool forceRefresh = false}) async {
    if (showId.isEmpty) return null;

    if (!forceRefresh) {
      final cached =
          _memo[showId] ?? _decodeShow(PodcastCache.readAny(_showKey(showId)));
      if (cached != null) {
        _memo[showId] = cached;
        if (PodcastCache.isStale(_showKey(showId), PodcastCache.showTtlMinutes)) {
          _revalidate(showId);
        }
        return cached;
      }
    }

    final fresh = await YtPodcastApi.showDetail(showId);
    if (fresh != null) {
      _store(showId, fresh);
      return fresh;
    }
    // Network failed — serve whatever we have, however old.
    return _decodeShow(PodcastCache.readAny(_showKey(showId)));
  }

  static void _revalidate(String showId) {
    if (!_revalidating.add(showId)) return;
    YtPodcastApi.showDetail(showId).then((fresh) {
      if (fresh == null) return;
      _store(showId, fresh);
      for (final fn in List.of(_showListeners)) {
        fn(fresh);
      }
    }).whenComplete(() => _revalidating.remove(showId));
  }

  /// Re-fetches followed shows whose stored metadata is old, so a follow's
  /// expired cover URL gets replaced and older follows gain the creator's
  /// avatar. Bounded and sequential — this is housekeeping, not a feed load.
  static Future<void> healFollowed(List<PodcastShow> shows) async {
    for (final show in shows.take(8)) {
      if (!_revalidating.add(show.id)) continue;
      try {
        final fresh = await YtPodcastApi.showDetail(show.id);
        if (fresh != null) _store(show.id, fresh);
      } finally {
        _revalidating.remove(show.id);
      }
    }
  }

  static void _store(String showId, PodcastShowDetail detail) {
    _memo[showId] = detail;
    PodcastCache.write(_showKey(showId), {
      'show': detail.show.toMap(),
      'episodes': detail.episodes.map((e) => e.toMap()).toList(),
      // Persisted so a page restored from cache can still load older
      // episodes without re-fetching the first page first.
      'continuation': detail.continuation,
    });
    // A fresh page is the moment to repair the matching follow (current
    // signed cover URL, avatar, author). No-op for shows not followed.
    PodcastLibraryService.refreshMetadata(detail.show);
  }

  static PodcastShowDetail? _decodeShow(dynamic raw) {
    if (raw is! Map) return null;
    final show = raw['show'];
    if (show is! Map) return null;
    return PodcastShowDetail(
      show: PodcastShow.fromMap(show),
      episodes: (raw['episodes'] as List? ?? const [])
          .whereType<Map>()
          .map(PodcastEpisode.fromMap)
          .toList(),
      continuation: raw['continuation'] as String?,
    );
  }

  /// Loads the next page of a show's back catalogue and folds it into the
  /// cached page, so scrolling back stays put across a screen reopen.
  /// Returns null when there is nothing more or the request failed.
  static Future<PodcastShowDetail?> moreEpisodes(
      PodcastShowDetail detail) async {
    final next = await YtPodcastApi.moreEpisodes(detail);
    if (next == null) return null;
    _store(detail.show.id, next);
    return next;
  }

  /// The Discover feed as topic shelves.
  static Future<List<PodcastShelf>> discover({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final decoded = _decodeShelves(PodcastCache.readAny(_discoverKey));
      if (decoded.isNotEmpty) {
        if (PodcastCache.isStale(_discoverKey, PodcastCache.discoverTtlMinutes) &&
            !_discoverRefreshing) {
          _discoverRefreshing = true;
          YtPodcastApi.discover().then((fresh) {
            if (fresh.isNotEmpty) {
              PodcastCache.write(_discoverKey, fresh.map(_encodeShelf).toList());
            }
          }).whenComplete(() => _discoverRefreshing = false);
        }
        return decoded;
      }
    }

    final fresh = await YtPodcastApi.discover();
    if (fresh.isNotEmpty) {
      PodcastCache.write(
          _discoverKey, fresh.map(_encodeShelf).toList());
      return fresh;
    }
    return _decodeShelves(PodcastCache.readAny(_discoverKey));
  }

  static Map<String, dynamic> _encodeShelf(PodcastShelf s) => {
        'title': s.title,
        'shows': s.shows.map((x) => x.toMap()).toList(),
        'episodes': s.episodes.map((x) => x.toMap()).toList(),
      };

  static List<PodcastShelf> _decodeShelves(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => PodcastShelf(
              title: (m['title'] ?? '').toString(),
              shows: (m['shows'] as List? ?? const [])
                  .whereType<Map>()
                  .map(PodcastShow.fromMap)
                  .toList(),
              episodes: (m['episodes'] as List? ?? const [])
                  .whereType<Map>()
                  .map(PodcastEpisode.fromMap)
                  .toList(),
            ))
        .where((s) => !s.isEmpty)
        .toList();
  }

  /// The newest episodes across every followed show, newest first.
  ///
  /// Reads each show's cached page where possible, so opening Home after the
  /// first load is a disk read rather than N network calls. [maxShows] bounds
  /// the fan-out for someone following dozens of podcasts.
  static Future<List<PodcastEpisode>> latestFrom(
    List<PodcastShow> shows, {
    int perShow = 3,
    int maxShows = 12,
    bool forceRefresh = false,
  }) async {
    if (shows.isEmpty) return const [];
    final details = await Future.wait(shows
        .take(maxShows)
        .map((s) => showDetail(s.id, forceRefresh: forceRefresh)));

    final out = <PodcastEpisode>[];
    for (var i = 0; i < details.length; i++) {
      final d = details[i];
      if (d == null) continue;
      final show = shows[i];
      out.addAll(d.episodes.take(perShow).map((e) => e.copyWith(
            showId: e.showId.isEmpty ? show.id : e.showId,
            showTitle: e.showTitle.isEmpty ? show.title : e.showTitle,
            showArtwork: e.showArtwork.isEmpty ? show.artwork : e.showArtwork,
          )));
    }

    // Show pages already list newest first, so episodes with no parseable
    // date keep their feed order rather than sinking to the bottom.
    out.sort((a, b) {
      final ad = a.publishedAt;
      final bd = b.publishedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return out;
  }

  /// Fills in the description/duration a search row didn't carry, by browsing
  /// the episode's own page. Returns [episode] unchanged if that fails.
  static Future<PodcastEpisode> hydrate(PodcastEpisode episode) async {
    if (episode.description.isNotEmpty && episode.duration > Duration.zero) {
      return episode;
    }
    final browseId = episode.browseId.isNotEmpty
        ? episode.browseId
        : 'MPED${episode.id}';
    final detail = await YtPodcastApi.episodeDetail(browseId);
    if (detail == null) return episode;
    return episode.copyWith(
      description:
          episode.description.isNotEmpty ? episode.description : detail.description,
      duration: episode.duration > Duration.zero ? episode.duration : detail.duration,
      showId: episode.showId.isNotEmpty ? episode.showId : detail.showId,
      showTitle:
          episode.showTitle.isNotEmpty ? episode.showTitle : detail.showTitle,
      artwork: episode.artwork.isNotEmpty ? episode.artwork : detail.artwork,
      publishedAt: episode.publishedAt ?? detail.publishedAt,
      publishedLabel: episode.publishedLabel.isNotEmpty
          ? episode.publishedLabel
          : detail.publishedLabel,
    );
  }
}
