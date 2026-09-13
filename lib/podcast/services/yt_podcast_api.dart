// podcast/services/yt_podcast_api.dart
//
// On-device YouTube Music PODCAST client. A sibling of the music
// YtMusicService, never a caller of it: podcasts live behind different search
// filters, different browse ids, and — crucially — a different renderer for
// their rows, so sharing a parser would mean bending one domain's shapes
// around the other's. Nothing here can change a music search result.
//
// Endpoints used (all verified against live responses):
//
//   search  params EgWKAQJQ…  → shows    (musicResponsiveListItemRenderer,
//                                          browseId "MPSPPL…")
//   search  params EgWKAQJI…  → episodes (musicResponsiveListItemRenderer,
//                                          watchEndpoint videoId + "MPED…")
//   browse  MPSPPL…           → show page: musicResponsiveHeaderRenderer +
//                                musicMultiRowListItemRenderer episode rows
//                                (title, description, duration, publish date)
//   browse  MPED…             → one episode's page (full description)
//   browse  FEmusic_non_music_audio
//                             → the podcast Discover feed: ~20 topic shelves
//                                ("Popular shows", "Meditation", "Thrillers")
//
// Parsing follows the same defensive discipline as the music client —
// recursive key collection plus per-field guards — so one shape change
// degrades a field instead of discarding the response.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'podcast_artwork.dart';

/// A Discover shelf: a titled row of shows and/or episodes.
class PodcastShelf {
  final String title;
  final List<PodcastShow> shows;
  final List<PodcastEpisode> episodes;

  const PodcastShelf({
    required this.title,
    this.shows = const [],
    this.episodes = const [],
  });

  bool get isEmpty => shows.isEmpty && episodes.isEmpty;
}

/// A resolved show page: header metadata plus its episode feed.
///
/// [continuation] is the token for the NEXT page of the back catalogue, or
/// null when the feed is exhausted. Paging is opt-in — each page is roughly a
/// megabyte, so the show screen loads older episodes only when asked.
class PodcastShowDetail {
  final PodcastShow show;
  final List<PodcastEpisode> episodes;
  final String? continuation;

  const PodcastShowDetail({
    required this.show,
    required this.episodes,
    this.continuation,
  });

  bool get hasMore => (continuation ?? '').isNotEmpty;

  /// Returns a copy with [more] appended, de-duplicated by episode id.
  PodcastShowDetail withMore(List<PodcastEpisode> more, String? next) {
    final seen = episodes.map((e) => e.id).toSet();
    return PodcastShowDetail(
      show: show,
      episodes: [...episodes, ...more.where((e) => seen.add(e.id))],
      continuation: next,
    );
  }
}

class YtPodcastApi {
  // ── Request plumbing ──────────────────────────────────────────────────────
  // Deliberately duplicated rather than imported from the music client: this
  // file must be able to change its client version, timeouts or retry policy
  // without any chance of altering music search. It is ~40 lines.

  static const _defaultClientVersion = '1.20240101.01.00';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Search filter params. Same envelope as the music filters, differing only
  /// in the type byte: II=songs, IY=albums, JQ=podcasts, JI=episodes.
  static const _showsParams = 'EgWKAQJQAWoMEA4QChADEAQQCRAF';
  static const _episodesParams = 'EgWKAQJIAWoMEA4QChADEAQQCRAF';

  /// YT Music's own podcast landing page.
  static const _discoverBrowseId = 'FEmusic_non_music_audio';

  /// Scraped from the page only after a request fails, so the happy path is a
  /// single round-trip and a stale version can still self-heal.
  static String? _dynamicClientVersion;

  static String get _clientVersion =>
      _dynamicClientVersion ?? _defaultClientVersion;

  static Map<String, dynamic> get _context => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion,
          'hl': 'en',
          'gl': 'US',
        }
      };

  static const _headers = {
    'Content-Type': 'application/json',
    'Origin': 'https://music.youtube.com',
    'User-Agent': _ua,
  };

  /// One youtubei POST. Returns decoded JSON, or null on any failure.
  static Future<dynamic> _post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://music.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: _headers,
            body: jsonEncode({'context': _context, ...body}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  /// Runs [attempt]; on failure refreshes the client version once and retries.
  static Future<T?> _withRetry<T>(Future<T?> Function() attempt) async {
    final first = await attempt();
    if (first != null) return first;
    if (await _refreshClientVersion()) return attempt();
    return null;
  }

  static Future<bool> _refreshClientVersion() async {
    try {
      final res = await http.get(
        Uri.parse('https://music.youtube.com/'),
        headers: const {'User-Agent': _ua, 'Cookie': 'CONSENT=YES+1'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final ver = RegExp(r'"INNERTUBE_CLIENT_VERSION":\s*"([^"]+)"')
          .firstMatch(res.body)
          ?.group(1);
      if (ver != null && ver.isNotEmpty && ver != _clientVersion) {
        _dynamicClientVersion = ver;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Searches for podcast SHOWS. Empty list on any failure.
  static Future<List<PodcastShow>> searchShows(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final data = await _withRetry(
        () => _post('search', {'query': q, 'params': _showsParams}));
    if (data == null) return const [];
    try {
      return _parseShowRows(data);
    } catch (_) {
      return const [];
    }
  }

  /// Searches for podcast EPISODES. Empty list on any failure.
  static Future<List<PodcastEpisode>> searchEpisodes(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final data = await _withRetry(
        () => _post('search', {'query': q, 'params': _episodesParams}));
    if (data == null) return const [];
    try {
      return _parseEpisodeRows(data);
    } catch (_) {
      return const [];
    }
  }

  /// Fetches a show page (`MPSPPL…`): header + episode feed. Null on failure.
  ///
  /// YouTube is inconsistent about how much of the feed the first page
  /// carries — the same request returns 99 episodes most of the time and 20
  /// every so often. A page that comes back short is topped up with one
  /// continuation, so a show never renders a suspiciously stubby feed.
  static Future<PodcastShowDetail?> showDetail(String browseId) async {
    final id = browseId.trim();
    if (id.isEmpty) return null;
    final data = await _withRetry(() => _post('browse', {'browseId': id}));
    if (data == null) return null;
    try {
      final detail = _parseShowDetail(data, id);
      if (detail == null) return null;
      if (detail.episodes.length >= _shortPageThreshold || !detail.hasMore) {
        return detail;
      }
      return await moreEpisodes(detail) ?? detail;
    } catch (_) {
      return null;
    }
  }

  /// A first page smaller than this is treated as truncated and topped up.
  static const _shortPageThreshold = 40;

  /// Fetches the next page of [detail]'s back catalogue. Null when there is
  /// nothing more, or on any failure — the caller keeps what it already has.
  static Future<PodcastShowDetail?> moreEpisodes(
      PodcastShowDetail detail) async {
    if (!detail.hasMore) return null;
    final data = await _post('browse', {'continuation': detail.continuation});
    if (data == null) return null;
    try {
      final more = _parseEpisodeRows(data, show: detail.show);
      if (more.isEmpty) {
        // No progress — drop the token so the caller stops asking.
        return PodcastShowDetail(show: detail.show, episodes: detail.episodes);
      }
      var next = _continuationToken(data);
      if (next == detail.continuation) next = null; // never loop on one token
      return detail.withMore(more, next);
    } catch (_) {
      return null;
    }
  }

  /// The continuation token for the next page, from either shape YouTube
  /// uses. Podcast show pages still emit the LEGACY `nextContinuationData`,
  /// so that is checked first; the current `continuationItemRenderer` shape
  /// is the fallback.
  static String? _continuationToken(dynamic data) {
    for (final c in _all(data, 'nextContinuationData')) {
      if (c is! Map) continue;
      final tok = c['continuation'];
      if (tok is String && tok.isNotEmpty) return tok;
    }
    for (final c in _all(data, 'continuationItemRenderer')) {
      if (c is! Map) continue;
      final tok = c['continuationEndpoint']?['continuationCommand']?['token'];
      if (tok is String && tok.isNotEmpty) return tok;
    }
    return null;
  }

  /// Fetches one episode's own page (`MPED…`) for the full description and
  /// duration that list rows omit. Null on failure.
  static Future<PodcastEpisode?> episodeDetail(String browseId) async {
    final id = browseId.trim();
    if (id.isEmpty) return null;
    final data = await _withRetry(() => _post('browse', {'browseId': id}));
    if (data == null) return null;
    try {
      return _parseEpisodeDetail(data, id);
    } catch (_) {
      return null;
    }
  }

  /// The Discover feed — YT Music's podcast landing page, as topic shelves.
  /// Empty list on any failure (callers fall back to seeded searches).
  static Future<List<PodcastShelf>> discover() async {
    final data =
        await _withRetry(() => _post('browse', {'browseId': _discoverBrowseId}));
    if (data == null) return const [];
    try {
      return _parseShelves(data);
    } catch (_) {
      return const [];
    }
  }

  // ── Tree walking ──────────────────────────────────────────────────────────

  /// Collects every value stored under [key] anywhere in the tree.
  static void _collect(dynamic node, String key, List<dynamic> acc) {
    if (node is Map) {
      node.forEach((k, v) {
        if (k == key) acc.add(v);
        _collect(v, key, acc);
      });
    } else if (node is List) {
      for (final x in node) {
        _collect(x, key, acc);
      }
    }
  }

  static List<dynamic> _all(dynamic node, String key) {
    final acc = <dynamic>[];
    _collect(node, key, acc);
    return acc;
  }

  /// Concatenated text of a `{runs:[…]}` object (episode titles and dates are
  /// frequently split across runs, so joining beats taking the first).
  static String _runsText(dynamic textObj) {
    if (textObj is Map && textObj['runs'] is List) {
      return (textObj['runs'] as List)
          .map((r) => r is Map ? (r['text'] ?? '').toString() : '')
          .join()
          .trim();
    }
    return '';
  }

  static List<dynamic> _runs(dynamic textObj) =>
      (textObj is Map && textObj['runs'] is List)
          ? textObj['runs'] as List
          : const [];

  /// Largest thumbnail under [node]. Picks by pixel area rather than list
  /// position — podcast thumbnail lists are not always ascending.
  static String _bestThumb(dynamic node) {
    var best = '';
    var bestArea = -1;
    for (final list in _all(node ?? const {}, 'thumbnails')) {
      if (list is! List) continue;
      for (final t in list) {
        if (t is! Map) continue;
        final url = (t['url'] ?? '').toString();
        if (url.isEmpty) continue;
        final area = ((t['width'] as num?)?.toInt() ?? 0) *
            ((t['height'] as num?)?.toInt() ?? 0);
        if (area > bestArea) {
          bestArea = area;
          best = url;
        }
      }
    }
    return best;
  }

  /// Episode frames are stored in their permanent unsigned form — see
  /// [PodcastArtwork.canonical] for why the signed form can't be kept.
  static String stableEpisodeArt(String url) => PodcastArtwork.canonical(url);

  static String? _pageType(Map run) {
    final cfg = run['navigationEndpoint']?['browseEndpoint']
            ?['browseEndpointContextSupportedConfigs']
        ?['browseEndpointContextMusicConfig'];
    return cfg is Map ? cfg['pageType'] as String? : null;
  }

  static String? _browseIdOf(Map run) =>
      run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;

  /// First browse id under [node] whose page type matches [pageType], or whose
  /// id carries [prefix] (the type config is occasionally absent).
  static String _findBrowseId(dynamic node,
      {required String pageType, required String prefix}) {
    for (final b in _all(node, 'browseEndpoint')) {
      if (b is! Map) continue;
      final id = b['browseId'];
      if (id is! String || id.isEmpty) continue;
      final pt = b['browseEndpointContextSupportedConfigs']
          ?['browseEndpointContextMusicConfig']?['pageType'];
      if (pt == pageType || id.startsWith(prefix)) return id;
    }
    return '';
  }

  static String _findVideoId(dynamic node) {
    for (final w in _all(node, 'watchEndpoint')) {
      if (w is Map && w['videoId'] is String && (w['videoId'] as String).isNotEmpty) {
        return w['videoId'] as String;
      }
    }
    return '';
  }

  static String _flexText(dynamic item, int column) {
    final flex = item is Map ? item['flexColumns'] : null;
    if (flex is! List || flex.length <= column) return '';
    return _runsText(
        flex[column]?['musicResponsiveListItemFlexColumnRenderer']?['text']);
  }

  static List<dynamic> _flexRuns(dynamic item, int column) {
    final flex = item is Map ? item['flexColumns'] : null;
    if (flex is! List || flex.length <= column) return const [];
    return _runs(
        flex[column]?['musicResponsiveListItemFlexColumnRenderer']?['text']);
  }

  // ── Show parsing ──────────────────────────────────────────────────────────

  static List<PodcastShow> _parseShowRows(dynamic data) {
    final shows = <PodcastShow>[];
    final seen = <String>{};
    for (final it in _all(data, 'musicResponsiveListItemRenderer')) {
      if (it is! Map) continue;
      final show = _parseShowRow(it);
      if (show != null && seen.add(show.id)) shows.add(show);
    }
    return shows;
  }

  static PodcastShow? _parseShowRow(Map item) {
    final id = _findBrowseId(item,
        pageType: 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE',
        prefix: 'MPSPPL');
    if (id.isEmpty) return null;

    final title = _flexText(item, 0);
    if (title.isEmpty) return null;

    // Second column is the creator. Drop separator runs and any duplicate of
    // the title (single-show channels repeat their own name).
    var author = '';
    for (final r in _flexRuns(item, 1)) {
      if (r is! Map) continue;
      final text = (r['text'] ?? '').toString().trim();
      if (text.isEmpty || text == '•' || text.toLowerCase() == 'podcast') {
        continue;
      }
      author = text;
      break;
    }

    return PodcastShow(
      id: id,
      title: title,
      author: author,
      artwork: _bestThumb(item['thumbnail']),
      channelId: _findBrowseId(item,
          pageType: 'MUSIC_PAGE_TYPE_USER_CHANNEL', prefix: 'UC'),
    );
  }

  /// Grid/carousel card form of a show (`musicTwoRowItemRenderer`), used on
  /// the Discover shelves.
  static PodcastShow? _parseShowCard(Map item) {
    final id = _findBrowseId(item,
        pageType: 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE',
        prefix: 'MPSPPL');
    if (id.isEmpty) return null;
    final title = _runsText(item['title']);
    if (title.isEmpty) return null;
    return PodcastShow(
      id: id,
      title: title,
      author: _runsText(item['subtitle']),
      artwork: _bestThumb(item['thumbnailRenderer'] ?? item['thumbnail']),
      channelId: _findBrowseId(item['subtitle'],
          pageType: 'MUSIC_PAGE_TYPE_USER_CHANNEL', prefix: 'UC'),
    );
  }

  static PodcastShowDetail? _parseShowDetail(dynamic data, String browseId) {
    final headers = _all(data, 'musicResponsiveHeaderRenderer');
    var title = '';
    var author = '';
    var cover = '';
    var channelId = '';
    var description = '';
    var avatar = '';

    if (headers.isNotEmpty && headers.first is Map) {
      final h = headers.first as Map;
      title = _runsText(h['title']);
      author = _runsText(h['straplineTextOne']);
      cover = _bestThumb(h['thumbnail']);
      avatar = _bestThumb(h['straplineThumbnail']);
      channelId = _findBrowseId(h['straplineTextOne'],
          pageType: 'MUSIC_PAGE_TYPE_USER_CHANNEL', prefix: 'UC');
      description = _runsText(
          h['description']?['musicDescriptionShelfRenderer']?['description']);
    }
    // Header description shelves sometimes sit outside the header node.
    if (description.isEmpty) {
      for (final s in _all(data, 'musicDescriptionShelfRenderer')) {
        if (s is! Map) continue;
        final text = _runsText(s['description']);
        if (text.isNotEmpty) {
          description = text;
          break;
        }
      }
    }

    final show = PodcastShow(
      id: browseId,
      title: title,
      author: author,
      artwork: cover,
      description: description,
      channelId: channelId,
      avatar: avatar,
    );

    final episodes = _parseEpisodeRows(data, show: show);
    if (title.isEmpty && episodes.isEmpty) return null;
    return PodcastShowDetail(
      show: show,
      episodes: episodes,
      continuation: _continuationToken(data),
    );
  }

  // ── Episode parsing ───────────────────────────────────────────────────────

  /// Parses every episode row in [data], from BOTH shapes YouTube uses:
  /// `musicMultiRowListItemRenderer` (show pages — carries description and
  /// duration) and `musicResponsiveListItemRenderer` (search results).
  static List<PodcastEpisode> _parseEpisodeRows(dynamic data,
      {PodcastShow? show}) {
    final episodes = <PodcastEpisode>[];
    final seen = <String>{};

    void add(PodcastEpisode? e) {
      if (e == null || e.id.isEmpty) return;
      if (seen.add(e.id)) episodes.add(e);
    }

    for (final it in _all(data, 'musicMultiRowListItemRenderer')) {
      if (it is Map) add(_parseMultiRowEpisode(it, show));
    }
    for (final it in _all(data, 'musicResponsiveListItemRenderer')) {
      if (it is Map) add(_parseListEpisode(it, show));
    }
    return episodes;
  }

  /// Show-page episode row: the rich one — title, description, duration,
  /// publish date and a 16:9 frame.
  static PodcastEpisode? _parseMultiRowEpisode(Map item, PodcastShow? show) {
    final videoId = _findVideoId(item);
    if (videoId.isEmpty) return null;
    final title = _runsText(item['title']);
    if (title.isEmpty) return null;

    // Subtitle is "3.1M views • 3d ago" — the date is the last meaningful run.
    var dateLabel = '';
    for (final r in _runs(item['subtitle'])) {
      if (r is! Map) continue;
      final text = (r['text'] ?? '').toString().trim();
      if (text.isEmpty || text == '•') continue;
      if (text.toLowerCase().contains('view')) continue;
      dateLabel = text;
    }

    return PodcastEpisode(
      id: videoId,
      browseId: _findBrowseId(item['title'],
          pageType: 'MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE',
          prefix: 'MPED'),
      title: title,
      showId: show?.id ??
          _findBrowseId(item,
              pageType: 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE',
              prefix: 'MPSPPL'),
      showTitle: show?.title ?? '',
      artwork: stableEpisodeArt(_bestThumb(item['thumbnail'])),
      showArtwork: show?.artwork ?? '',
      description: _runsText(item['description']),
      duration: _durationFrom(item),
      publishedAt: parseRelativeDate(dateLabel),
      publishedLabel: dateLabel,
    );
  }

  /// Search-result episode row: title + "date • show", no duration.
  static PodcastEpisode? _parseListEpisode(Map item, PodcastShow? show) {
    final videoId = _findVideoId(item);
    if (videoId.isEmpty) return null;

    // Guard against show rows, which share this renderer in show searches:
    // a show row has no watchEndpoint, so reaching here already implies an
    // episode, but a playlist-level play button could also carry one.
    final title = _flexText(item, 0);
    if (title.isEmpty) return null;

    var dateLabel = '';
    var showTitle = show?.title ?? '';
    var showId = show?.id ?? '';
    for (final r in _flexRuns(item, 1)) {
      if (r is! Map) continue;
      final text = (r['text'] ?? '').toString().trim();
      if (text.isEmpty || text == '•') continue;
      if (_pageType(r) == 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE') {
        showTitle = text;
        showId = _browseIdOf(r) ?? showId;
      } else if (dateLabel.isEmpty && !text.toLowerCase().contains('view')) {
        dateLabel = text;
      }
    }

    return PodcastEpisode(
      id: videoId,
      browseId: _findBrowseId(item,
          pageType: 'MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE',
          prefix: 'MPED'),
      title: title,
      showId: showId,
      showTitle: showTitle,
      artwork: stableEpisodeArt(_bestThumb(item['thumbnail'])),
      showArtwork: show?.artwork ?? '',
      duration: _durationFrom(item),
      publishedAt: parseRelativeDate(dateLabel),
      publishedLabel: dateLabel,
    );
  }

  static PodcastEpisode? _parseEpisodeDetail(dynamic data, String browseId) {
    final headers = _all(data, 'musicResponsiveHeaderRenderer');
    if (headers.isEmpty || headers.first is! Map) return null;
    final h = headers.first as Map;

    final title = _runsText(h['title']);
    if (title.isEmpty) return null;

    var description = '';
    for (final s in _all(data, 'musicDescriptionShelfRenderer')) {
      if (s is! Map) continue;
      final text = _runsText(s['description']);
      if (text.isNotEmpty) {
        description = text;
        break;
      }
    }

    var dateLabel = '';
    for (final r in _runs(h['subtitle'])) {
      if (r is! Map) continue;
      final text = (r['text'] ?? '').toString().trim();
      if (text.isEmpty || text == '•' || text.toLowerCase().contains('view')) {
        continue;
      }
      dateLabel = text;
    }

    // The page's own videoId is only in the play button; fall back to the
    // browseId, which is literally "MPED" + videoId.
    var videoId = _findVideoId(data);
    if (videoId.isEmpty && browseId.startsWith('MPED')) {
      videoId = browseId.substring(4);
    }
    if (videoId.isEmpty) return null;

    return PodcastEpisode(
      id: videoId,
      browseId: browseId,
      title: title,
      showId: _findBrowseId(h['straplineTextOne'],
          pageType: 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE',
          prefix: 'MPSPPL'),
      showTitle: _runsText(h['straplineTextOne']),
      artwork: stableEpisodeArt(_bestThumb(h['thumbnail'])),
      description: description,
      duration: _durationFrom(data),
      publishedAt: parseRelativeDate(dateLabel),
      publishedLabel: dateLabel,
    );
  }

  // ── Discover shelves ──────────────────────────────────────────────────────

  static List<PodcastShelf> _parseShelves(dynamic data) {
    final shelves = <PodcastShelf>[];
    for (final c in _all(data, 'musicCarouselShelfRenderer')) {
      if (c is! Map) continue;
      final title = _shelfTitle(c['header']);
      if (title.isEmpty) continue;

      final shows = <PodcastShow>[];
      final seenShows = <String>{};
      for (final card in _all(c['contents'], 'musicTwoRowItemRenderer')) {
        if (card is! Map) continue;
        final s = _parseShowCard(card);
        if (s != null && seenShows.add(s.id)) {
          shows.add(s.copyWith(category: title));
        }
      }

      final episodes = <PodcastEpisode>[];
      final seenEps = <String>{};
      for (final row in _all(c['contents'], 'musicMultiRowListItemRenderer')) {
        if (row is! Map) continue;
        final e = _parseMultiRowEpisode(row, null);
        if (e != null && seenEps.add(e.id)) episodes.add(e);
      }

      final shelf =
          PodcastShelf(title: title, shows: shows, episodes: episodes);
      if (!shelf.isEmpty) shelves.add(shelf);
    }
    return shelves;
  }

  static String _shelfTitle(dynamic header) {
    for (final r in _all(header, 'runs')) {
      if (r is List && r.isNotEmpty && r.first is Map) {
        final text = (r.first['text'] ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  // ── Field parsers ─────────────────────────────────────────────────────────

  /// Pulls a duration out of any playback-progress renderer under [node], then
  /// falls back to a fixed column. Podcast durations arrive as prose
  /// ("2 hr 16 min"), not the "m:ss" music uses.
  static Duration _durationFrom(dynamic node) {
    for (final p in _all(node, 'musicPlaybackProgressRenderer')) {
      if (p is! Map) continue;
      final text = _runsText(p['durationText']);
      final d = parseDuration(text);
      if (d > Duration.zero) return d;
    }
    for (final f in _all(node, 'musicResponsiveListItemFixedColumnRenderer')) {
      if (f is! Map) continue;
      final d = parseDuration(_runsText(f['text']));
      if (d > Duration.zero) return d;
    }
    return Duration.zero;
  }

  static final _clockRe = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');
  static final _unitRe =
      RegExp(r'(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b');

  /// Parses both the clock form ("1:02:33") and the prose form YouTube uses
  /// for podcasts ("2 hr 16 min", "45 min", "38 sec"). Zero when unparseable.
  static Duration parseDuration(String raw) {
    final text = raw.replaceAll('•', '').trim();
    if (text.isEmpty) return Duration.zero;

    if (_clockRe.hasMatch(text)) {
      final parts = text.split(':').map(int.parse).toList();
      if (parts.length == 2) {
        return Duration(minutes: parts[0], seconds: parts[1]);
      }
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }

    var total = Duration.zero;
    for (final m in _unitRe.allMatches(text.toLowerCase())) {
      final value = int.tryParse(m.group(1) ?? '') ?? 0;
      final unit = m.group(2)!;
      if (unit.startsWith('h')) {
        total += Duration(hours: value);
      } else if (unit.startsWith('m')) {
        total += Duration(minutes: value);
      } else {
        total += Duration(seconds: value);
      }
    }
    return total;
  }

  static final _relativeRe = RegExp(
      r'^(\d+)\s*(second|sec|minute|min|hour|hr|day|d|week|w|month|mo|year|y)s?\s*ago$');
  static final _monthDayRe =
      RegExp(r'^([A-Za-z]{3,})\s+(\d{1,2})(?:,\s*(\d{4}))?$');

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Best-effort absolute date from the labels YouTube renders:
  /// "3d ago", "2 hours ago", "Aug 27", "Aug 27, 2024". Null when
  /// unrecognised — callers show [PodcastEpisode.publishedLabel] instead, so a
  /// miss costs nothing visually and only weakens recency ranking.
  static DateTime? parseRelativeDate(String raw, {DateTime? now}) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    final today = now ?? DateTime.now();

    final rel = _relativeRe.firstMatch(text);
    if (rel != null) {
      final n = int.tryParse(rel.group(1) ?? '') ?? 0;
      switch (rel.group(2)!) {
        case 'second':
        case 'sec':
          return today.subtract(Duration(seconds: n));
        case 'minute':
        case 'min':
          return today.subtract(Duration(minutes: n));
        case 'hour':
        case 'hr':
          return today.subtract(Duration(hours: n));
        case 'day':
        case 'd':
          return today.subtract(Duration(days: n));
        case 'week':
        case 'w':
          return today.subtract(Duration(days: 7 * n));
        case 'month':
        case 'mo':
          return today.subtract(Duration(days: 30 * n));
        default:
          return today.subtract(Duration(days: 365 * n));
      }
    }

    final md = _monthDayRe.firstMatch(raw.trim());
    if (md != null) {
      final month = _months[md.group(1)!.toLowerCase().substring(0, 3)];
      final day = int.tryParse(md.group(2) ?? '');
      if (month != null && day != null) {
        final year = int.tryParse(md.group(3) ?? '') ??
            // No year means "this year" — unless that would be in the future,
            // in which case YouTube meant last year.
            (DateTime(today.year, month, day).isAfter(today)
                ? today.year - 1
                : today.year);
        return DateTime(year, month, day);
      }
    }
    return null;
  }
}
