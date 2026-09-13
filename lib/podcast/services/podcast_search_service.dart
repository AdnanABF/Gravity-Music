// podcast/services/podcast_search_service.dart
//
// Podcast search. A sibling of the music SearchService, never a wrapper of it:
// SearchService.autocomplete() keeps returning exactly the music SearchResults
// it always has, and nothing here calls it.
//
// The two result KINDS are kept apart rather than merged into one list,
// because a show and an episode are used differently — a show is opened, an
// episode is played — and the search screen renders them as separate sections.
// Creators are surfaced as a third grouping derived from the show results
// (the same publisher usually owns several shows).

import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'yt_podcast_api.dart';

/// A creator with the shows of theirs that matched.
class PodcastCreator {
  final String name;
  final String channelId;
  final List<PodcastShow> shows;

  const PodcastCreator({
    required this.name,
    required this.channelId,
    required this.shows,
  });

  String get artwork => shows.isEmpty ? '' : shows.first.artwork;
}

class PodcastSearchResults {
  final String query;
  final List<PodcastShow> shows;
  final List<PodcastEpisode> episodes;
  final List<PodcastCreator> creators;

  const PodcastSearchResults({
    required this.query,
    this.shows = const [],
    this.episodes = const [],
    this.creators = const [],
  });

  bool get isEmpty => shows.isEmpty && episodes.isEmpty && creators.isEmpty;

  static const empty = PodcastSearchResults(query: '');
}

class PodcastSearchService {
  static const _maxShows = 12;
  static const _maxEpisodes = 20;
  static const _maxCacheSize = 20;
  static const _ttlMinutes = 15;

  // Its own LRU, in its own map. The music search cache is a different static
  // in a different class and is never read or evicted from here.
  static final _cache =
      <String, ({PodcastSearchResults results, DateTime ts})>{};

  /// Searches shows and episodes concurrently. Returns empty results rather
  /// than throwing — the UI treats that as "no results".
  static Future<PodcastSearchResults> search(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return PodcastSearchResults.empty;

    final cached = _cache[key];
    if (cached != null) {
      if (DateTime.now().difference(cached.ts).inMinutes < _ttlMinutes) {
        _cache.remove(key);
        _cache[key] = cached; // touch (LRU)
        return cached.results;
      }
      _cache.remove(key);
    }

    try {
      final res = await Future.wait([
        YtPodcastApi.searchShows(query.trim()),
        YtPodcastApi.searchEpisodes(query.trim()),
      ]);
      final shows = (res[0] as List<PodcastShow>).take(_maxShows).toList();
      final episodes =
          (res[1] as List<PodcastEpisode>).take(_maxEpisodes).toList();

      final results = PodcastSearchResults(
        query: query.trim(),
        shows: shows,
        episodes: _attachShowArt(episodes, shows),
        creators: _creatorsFrom(shows),
      );

      if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
      _cache[key] = (results: results, ts: DateTime.now());
      return results;
    } catch (_) {
      return PodcastSearchResults(query: query.trim());
    }
  }

  /// Episode search rows carry a 16:9 video frame but no series cover. When
  /// the show also matched the query we can lend the episode its cover, so a
  /// row has something to fall back on.
  static List<PodcastEpisode> _attachShowArt(
      List<PodcastEpisode> episodes, List<PodcastShow> shows) {
    if (shows.isEmpty) return episodes;
    final byId = {for (final s in shows) s.id: s};
    return episodes.map((e) {
      final show = byId[e.showId];
      if (show == null || e.showArtwork.isNotEmpty) return e;
      return e.copyWith(showArtwork: show.artwork);
    }).toList();
  }

  /// Groups shows by creator, keeping only creators who are actually a
  /// grouping (named, and reachable) — a one-show creator adds nothing the
  /// show row doesn't already say, so those are dropped.
  static List<PodcastCreator> _creatorsFrom(List<PodcastShow> shows) {
    final byCreator = <String, List<PodcastShow>>{};
    for (final s in shows) {
      final name = s.author.trim();
      if (name.isEmpty || name.toLowerCase() == s.title.toLowerCase()) continue;
      byCreator.putIfAbsent(name.toLowerCase(), () => []).add(s);
    }
    final out = <PodcastCreator>[];
    byCreator.forEach((_, group) {
      if (group.length < 2) return;
      out.add(PodcastCreator(
        name: group.first.author,
        channelId: group.first.channelId,
        shows: group,
      ));
    });
    return out;
  }

  static void clearCache() => _cache.clear();
}
