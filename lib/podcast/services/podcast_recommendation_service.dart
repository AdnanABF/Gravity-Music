// podcast/services/podcast_recommendation_service.dart
//
// Podcast recommendations. Explicitly NOT the music recommender: that one
// seeds YouTube's radio from a videoId and re-ranks by artist affinity, which
// is meaningless here. Nobody wants "more tracks like this episode" — they
// want the next episode of a show they follow, or a different show about the
// same thing.
//
// Signals used (spec §10), in rough order of weight:
//
//   completion        finishing an episode is the strongest endorsement
//   following         an explicit subscription
//   listening time    minutes spent, not taps
//   abandonment       started and dropped ⇒ demote the show
//   recency           a show dropped 6 months ago shouldn't crowd out this week
//   topic affinity    categories of the shows you engage with, from the
//                     Discover shelves (which are topic-labelled)
//   creator affinity  same publisher, different show
//   episode recency   new episodes surface above the back catalogue
//   episode length    people have a habitual episode length; ranked toward it
//
// The whole thing is structured as a scored candidate pool so new signals can
// be added later without restructuring (spec: "build it so it can evolve").
// Music's RecommendationService is untouched and unaware of this file.

import '../models/episode_progress.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'podcast_cache.dart';
import 'podcast_history_service.dart';
import 'podcast_library_service.dart';
import 'podcast_service.dart';
import 'yt_podcast_api.dart';

/// A recommended show plus the human reason it was chosen — the UI shows the
/// reason verbatim ("Because you listened to …"), so recommendations never
/// feel arbitrary.
class ShowRecommendation {
  final PodcastShow show;
  final String reason;
  final double score;

  const ShowRecommendation({
    required this.show,
    required this.reason,
    required this.score,
  });
}

/// Everything the podcast home needs, computed in one pass so the screen makes
/// a single call.
class PodcastRecommendations {
  /// Started but unfinished, most recent first.
  final List<PodcastHistoryEntry> continueListening;

  /// Latest episodes from followed shows.
  final List<PodcastEpisode> newFromYourShows;

  /// Episodes we think are worth playing next, from shows already engaged
  /// with but not yet listened to.
  final List<PodcastEpisode> pickedForYou;

  /// Shows to try, each with its reason.
  final List<ShowRecommendation> recommendedShows;

  /// Discover shelves, passed through for the browse surface.
  final List<PodcastShelf> shelves;

  const PodcastRecommendations({
    this.continueListening = const [],
    this.newFromYourShows = const [],
    this.pickedForYou = const [],
    this.recommendedShows = const [],
    this.shelves = const [],
  });

  bool get isEmpty =>
      continueListening.isEmpty &&
      newFromYourShows.isEmpty &&
      pickedForYou.isEmpty &&
      recommendedShows.isEmpty &&
      shelves.isEmpty;
}

class PodcastRecommendationService {
  /// Builds every home section. Network work is bounded: one Discover fetch
  /// (usually cached) plus at most [_maxShowFetches] show pages, which are
  /// themselves cached for a day.
  static Future<PodcastRecommendations> build({bool forceRefresh = false}) async {
    final following = PodcastLibraryService.following();
    final affinities = PodcastHistoryService.showAffinities();

    // Discover doubles as our topic index — its shelves are the only place
    // YouTube tells us what a show is ABOUT.
    final shelves = await PodcastService.discover(forceRefresh: forceRefresh);

    final newEpisodes = await PodcastService.latestFrom(
      following,
      forceRefresh: forceRefresh,
    );

    final picked = await _pickedForYou(affinities, following);

    return PodcastRecommendations(
      continueListening: PodcastHistoryService.continueListening(),
      newFromYourShows: newEpisodes,
      pickedForYou: picked,
      recommendedShows: _recommendShows(affinities, following, shelves),
      shelves: shelves,
    );
  }

  static const _maxShowFetches = 4;

  // ── Episodes to play next ─────────────────────────────────────────────────

  /// Unplayed episodes from the shows the listener is most engaged with,
  /// ranked by show engagement, episode recency, and how close the episode is
  /// to their habitual listening length.
  static Future<List<PodcastEpisode>> _pickedForYou(
    List<ShowAffinity> affinities,
    List<PodcastShow> following,
  ) async {
    // Engaged shows first; followed shows they haven't played yet fill in.
    final seeds = <PodcastShow>[];
    final seen = <String>{};
    for (final a in affinities.where((a) => a.score > 0)) {
      if (seen.add(a.show.id)) seeds.add(a.show);
      if (seeds.length >= _maxShowFetches) break;
    }
    for (final s in following) {
      if (seeds.length >= _maxShowFetches) break;
      if (seen.add(s.id)) seeds.add(s);
    }
    if (seeds.isEmpty) return const [];

    final details =
        await Future.wait(seeds.map((s) => PodcastService.showDetail(s.id)));

    final scoreByShow = {for (final a in affinities) a.show.id: a.score};
    final target = _preferredLength();

    final scored = <({PodcastEpisode ep, double score})>[];
    for (final d in details) {
      if (d == null) continue;
      final showScore = scoreByShow[d.show.id] ?? 0.3;
      // Only the front of the feed — a back catalogue of 300 episodes is not
      // a recommendation surface.
      for (final ep in d.episodes.take(12)) {
        final progress = PodcastHistoryService.progressFor(ep.id);
        // Already finished, or already in Continue Listening (which has its
        // own row) — don't recommend it again.
        if (progress != null &&
            (progress.completed ||
                progress.percent > EpisodeProgress.startedThreshold)) {
          continue;
        }
        scored.add((
          ep: ep.copyWith(
            showId: ep.showId.isEmpty ? d.show.id : ep.showId,
            showTitle: ep.showTitle.isEmpty ? d.show.title : ep.showTitle,
            showArtwork:
                ep.showArtwork.isEmpty ? d.show.artwork : ep.showArtwork,
          ),
          score: showScore * 1.0 +
              _recencyBoost(ep.publishedAt) +
              _lengthFit(ep.duration, target),
        ));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // One episode per show before a second from any — otherwise a single
    // prolific podcast fills the whole row.
    final out = <PodcastEpisode>[];
    final used = <String>{};
    for (final pass in [1, 2]) {
      for (final s in scored) {
        if (out.length >= 15) break;
        final key = s.ep.showId;
        final count = out.where((e) => e.showId == key).length;
        if (count >= pass) continue;
        if (used.add(s.ep.id)) out.add(s.ep);
      }
    }
    return out;
  }

  /// The listener's habitual episode length: the median duration of episodes
  /// they've finished. Null until they've finished a few.
  static Duration? _preferredLength() {
    final lengths = PodcastHistoryService.completed(limit: 40)
        .map((e) => e.progress.duration)
        .where((d) => d > Duration.zero)
        .toList()
      ..sort();
    if (lengths.length < 3) return null;
    return lengths[lengths.length ~/ 2];
  }

  /// 0…0.4 — a small nudge toward the listener's usual episode length. Kept
  /// deliberately weak: it should break ties, never override engagement.
  static double _lengthFit(Duration episode, Duration? target) {
    if (target == null || episode <= Duration.zero) return 0.0;
    final ratio = episode.inSeconds / target.inSeconds;
    final distance = (ratio - 1.0).abs();
    if (distance > 1.5) return 0.0;
    return 0.4 * (1.0 - (distance / 1.5));
  }

  /// 0…0.8 — new episodes rise, without burying a great one from last month.
  static double _recencyBoost(DateTime? published) {
    if (published == null) return 0.2; // unknown date: neutral-ish
    final days = DateTime.now().difference(published).inDays;
    if (days <= 2) return 0.8;
    if (days <= 7) return 0.6;
    if (days <= 30) return 0.35;
    if (days <= 120) return 0.15;
    return 0.0;
  }

  // ── Shows to try ──────────────────────────────────────────────────────────

  /// Candidate shows, scored and de-duplicated against what the listener
  /// already follows or plays.
  ///
  /// Three sources, in descending confidence:
  ///   • same TOPIC as a show they engage with (shelves are topic-labelled)
  ///   • same CREATOR as a show they engage with
  ///   • editorially popular, for a listener with no history yet
  static List<ShowRecommendation> _recommendShows(
    List<ShowAffinity> affinities,
    List<PodcastShow> following,
    List<PodcastShelf> shelves,
  ) {
    final known = <String>{
      ...following.map((s) => s.id),
      ...affinities.map((a) => a.show.id),
    };

    // Topic + creator index over everything Discover showed us.
    final byTopic = <String, List<PodcastShow>>{};
    final showsById = <String, PodcastShow>{};
    for (final shelf in shelves) {
      for (final s in shelf.shows) {
        showsById[s.id] = s;
        byTopic.putIfAbsent(shelf.title, () => []).add(s);
      }
    }

    // Which topics does the listener actually engage with? A show only counts
    // if Discover has placed it on a topic shelf.
    final topicScores = <String, double>{};
    final creatorScores = <String, double>{};
    final reasonForTopic = <String, String>{};
    final reasonForCreator = <String, String>{};

    for (final a in affinities.take(8)) {
      if (a.score <= 0) continue;
      final discovered = showsById[a.show.id];
      final title =
          a.show.title.isNotEmpty ? a.show.title : (discovered?.title ?? '');
      byTopic.forEach((topic, list) {
        if (!list.any((s) => s.id == a.show.id)) return;
        topicScores.update(topic, (v) => v + a.score,
            ifAbsent: () => a.score);
        reasonForTopic.putIfAbsent(topic, () => title);
      });
      final channel = discovered?.channelId ?? a.show.channelId;
      if (channel.isNotEmpty) {
        creatorScores.update(channel, (v) => v + a.score,
            ifAbsent: () => a.score);
        reasonForCreator.putIfAbsent(channel, () => title);
      }
    }
    // Following is an endorsement even without playback.
    for (final s in following) {
      if (s.channelId.isEmpty) continue;
      creatorScores.update(s.channelId, (v) => v + 0.5, ifAbsent: () => 0.5);
      reasonForCreator.putIfAbsent(s.channelId, () => s.title);
    }

    final scored = <String, ShowRecommendation>{};

    void offer(PodcastShow show, double score, String reason) {
      if (show.id.isEmpty || known.contains(show.id)) return;
      final existing = scored[show.id];
      if (existing != null && existing.score >= score) return;
      scored[show.id] =
          ShowRecommendation(show: show, reason: reason, score: score);
    }

    // Same topic.
    topicScores.forEach((topic, score) {
      for (final s in byTopic[topic] ?? const <PodcastShow>[]) {
        offer(s, 2.0 + score,
            'Because you listened to ${reasonForTopic[topic] ?? topic}');
      }
    });

    // Same creator.
    creatorScores.forEach((channelId, score) {
      for (final s in showsById.values) {
        if (s.channelId != channelId) continue;
        offer(s, 3.0 + score, 'More from ${s.author.isNotEmpty ? s.author : reasonForCreator[channelId] ?? 'this creator'}');
      }
    });

    // Cold start / filler: whatever Discover leads with.
    for (final shelf in shelves) {
      for (final s in shelf.shows) {
        offer(s, 0.5, shelf.title);
      }
    }

    final out = scored.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return out.take(20).toList();
  }

  /// "Listeners of X also like…" for a single show, used on the show page.
  /// Falls back to a title search, which YouTube answers with adjacent shows.
  static Future<List<PodcastShow>> similarTo(PodcastShow show) async {
    final shelves = await PodcastService.discover();
    final siblings = <PodcastShow>[];
    for (final shelf in shelves) {
      if (!shelf.shows.any((s) => s.id == show.id)) continue;
      siblings.addAll(shelf.shows.where((s) => s.id != show.id));
    }
    if (siblings.isNotEmpty) return siblings.take(12).toList();

    // Fallback is a network search — cached per show for a day, since the
    // show page used to fire one on every single open.
    final key = 'similar:${show.id}';
    final cached = PodcastCache.read(key, PodcastCache.showTtlMinutes);
    if (cached is List) {
      return cached.whereType<Map>().map(PodcastShow.fromMap).toList();
    }
    final query = show.author.isNotEmpty ? show.author : show.title;
    final found = (await YtPodcastApi.searchShows(query))
        .where((s) => s.id != show.id)
        .take(12)
        .toList();
    if (found.isNotEmpty) {
      PodcastCache.write(key, found.map((s) => s.toMap()).toList());
    }
    return found;
  }
}
