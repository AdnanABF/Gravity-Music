// podcast/ui/podcast_show_screen.dart
//
// The show page (spec §12): artwork, title, creator, description, a Follow
// button, and the episode feed with per-episode actions.
//
// Explicitly NOT the album page. An album is a fixed, ordered, ~45-minute
// object you play front to back; a show is an open-ended feed you follow, and
// its rows need publish dates, progress bars and descriptions that the album
// row has no concept of.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/common_widgets.dart';
import '../controllers/podcast_library_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import '../services/podcast_recommendation_service.dart';
import '../services/podcast_service.dart';
import '../services/yt_podcast_api.dart';
import 'podcast_episode_screen.dart';
import 'widgets/episode_actions.dart';
import 'widgets/episode_tile.dart';
import 'widgets/podcast_artwork_image.dart';
import 'widgets/podcast_mini_player.dart';
import 'widgets/show_card.dart';

class PodcastShowScreen extends StatefulWidget {
  final String showId;

  /// Optional title/art from the row that opened this page, so the header can
  /// render immediately instead of showing a spinner over a blank screen.
  final String title;
  final String artwork;

  const PodcastShowScreen({
    super.key,
    required this.showId,
    this.title = '',
    this.artwork = '',
  });

  @override
  State<PodcastShowScreen> createState() => _PodcastShowScreenState();
}

class _PodcastShowScreenState extends State<PodcastShowScreen> {
  PodcastShow? _show;
  PodcastShowDetail? _detail;
  List<PodcastEpisode> _episodes = const [];
  List<PodcastShow> _similar = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _expandedDescription = false;

  /// A background refresh of THIS show landed — swap in the new page, keeping
  /// any older episodes the user already paged in.
  void _onShowRefreshed(PodcastShowDetail fresh) {
    if (!mounted || fresh.show.id != widget.showId) return;
    setState(() {
      final loadedOlder = _episodes.length > fresh.episodes.length;
      _detail = loadedOlder
          ? fresh.withMore(_episodes, _detail?.continuation)
          : fresh;
      _show = fresh.show;
      _episodes = _detail!.episodes;
    });
  }

  @override
  void dispose() {
    PodcastService.removeShowListener(_onShowRefreshed);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    PodcastService.addShowListener(_onShowRefreshed);
    _show = widget.title.isEmpty
        ? null
        : PodcastShow(
            id: widget.showId, title: widget.title, artwork: widget.artwork);
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final detail = await PodcastService.showDetail(widget.showId,
        forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      if (detail != null) {
        _detail = detail;
        _show = detail.show;
        _episodes = detail.episodes;
      }
      _loading = false;
    });
    if (detail != null) {
      final similar = await PodcastRecommendationService.similarTo(detail.show);
      if (mounted) setState(() => _similar = similar);
    }
  }

  /// Pages the back catalogue on demand. Each page is roughly a megabyte, so
  /// this is a button rather than an infinite scroll.
  Future<void> _loadMore() async {
    final detail = _detail;
    if (detail == null || _loadingMore || !detail.hasMore) return;
    setState(() => _loadingMore = true);
    final next = await PodcastService.moreEpisodes(detail);
    if (!mounted) return;
    setState(() {
      if (next != null) {
        _detail = next;
        _episodes = next.episodes;
      } else {
        // Nothing more came back — drop the token so the button goes away
        // instead of retrying forever.
        _detail =
            PodcastShowDetail(show: detail.show, episodes: detail.episodes);
      }
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final show = _show;
    final player = Get.find<PodcastPlayerController>();
    final library = Get.find<PodcastLibraryController>();
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: ScreenWithPodcastMiniPlayer(
        child: RefreshIndicator(
          color: Colors.white,
          backgroundColor: AppColors.card,
          onRefresh: () => _load(forceRefresh: true),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.canvas,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: const AppBackButton(),
                title: Text(show?.title ?? widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.navTitle()),
              ),

              // ── Header ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenMargin, 8, AppSpacing.screenMargin, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PodcastArtworkImage(
                            url: show?.artwork ?? widget.artwork,
                            fallbackUrl: show?.avatar ?? '',
                            width: (width * 0.34).clamp(110.0, 190.0),
                            natural: true,
                            radius: AppRadius.lg,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PODCAST',
                                    style: AppText.label(
                                        color: AppColors.textTertiary)),
                                const SizedBox(height: 8),
                                Text(show?.title ?? widget.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.heading(size: 20)),
                                if ((show?.author ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  // The creator, with their channel picture —
                                  // it's how a listener tells the real show
                                  // from a same-named re-upload channel.
                                  Row(
                                    children: [
                                      if (show!.avatar.isNotEmpty) ...[
                                        PodcastArtworkImage(
                                          url: show.avatar,
                                          width: 22,
                                          ratio: 1,
                                          radius: AppRadius.pill,
                                          backdrop: false,
                                        ),
                                        const SizedBox(width: 7),
                                      ],
                                      Flexible(
                                        child: Text(show.author,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.subtitle(size: 13)),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 14),
                                if (show != null)
                                  Obx(() {
                                    library.following.length; // observe
                                    return FollowButton(
                                      following:
                                          library.isFollowing(show.id),
                                      onTap: () {
                                        AppHaptics.light();
                                        library.toggleFollow(show);
                                      },
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if ((show?.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.gutter),
                        GestureDetector(
                          onTap: () => setState(
                              () => _expandedDescription = !_expandedDescription),
                          child: Text(
                            show!.description,
                            maxLines: _expandedDescription ? null : 3,
                            overflow: _expandedDescription
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: AppText.subtitle(size: 13).copyWith(
                                height: 1.45,
                                color: AppColors.textSecondaryHi),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => setState(
                              () => _expandedDescription = !_expandedDescription),
                          child: Text(
                              _expandedDescription ? 'Show less' : 'Show more',
                              style: AppText.caption(
                                  color: AppColors.accent)),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.stackMd),
                    ],
                  ),
                ),
              ),

              // ── Episodes ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Latest Episodes',
                  action: _episodes.isEmpty
                      ? null
                      : GlassPillButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play newest',
                          onTap: () => player.play(_episodes.first),
                        ),
                ),
              ),

              if (_loading && _episodes.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: Colors.white)),
                  ),
                )
              else if (_episodes.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icons.podcasts_rounded,
                      title: 'No episodes',
                      message:
                          "We couldn't load this show's episodes right now.",
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: _episodes.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: AppSpacing.screenMargin,
                      endIndent: AppSpacing.screenMargin,
                      color: AppColors.borderSoft),
                  itemBuilder: (_, i) {
                    final ep = _withShow(_episodes[i]);
                    return EpisodeTile(
                      episode: ep,
                      showSeries: false,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PodcastEpisodeScreen(episode: ep))),
                      onPlay: () => _playOrPause(player, ep),
                      onMore: () => showEpisodeActions(context, ep),
                    );
                  },
                ),

              // ── Older episodes ────────────────────────────────────────
              if ((_detail?.hasMore ?? false) && _episodes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screenMargin,
                        16, AppSpacing.screenMargin, 0),
                    child: Center(
                      child: _loadingMore
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : GlassPillButton(
                              icon: Icons.expand_more_rounded,
                              label: 'Load older episodes',
                              onTap: _loadMore,
                            ),
                    ),
                  ),
                ),

              // ── Similar shows ─────────────────────────────────────────
              if (_similar.isNotEmpty) ...[
                const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.stackMd)),
                const SliverToBoxAdapter(
                    child: SectionHeader(title: 'You might also like')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: ShowCard.heightFor(context, 160),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenMargin),
                      itemCount: _similar.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.gutter),
                      itemBuilder: (_, i) => ShowCard(
                        show: _similar[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PodcastShowScreen(
                              showId: _similar[i].id,
                              title: _similar[i].title,
                              artwork: _similar[i].artwork,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),
        ),
      ),
    );
  }

  /// Episode rows on a show page inherit the series identity, which their own
  /// renderer doesn't repeat.
  PodcastEpisode _withShow(PodcastEpisode e) {
    final show = _show;
    if (show == null) return e;
    return e.copyWith(
      showId: e.showId.isEmpty ? show.id : e.showId,
      showTitle: e.showTitle.isEmpty ? show.title : e.showTitle,
      showArtwork: e.showArtwork.isEmpty ? show.artwork : e.showArtwork,
    );
  }

  void _playOrPause(PodcastPlayerController player, PodcastEpisode ep) {
    if (player.isCurrent(ep.id)) {
      player.togglePlayPause();
    } else {
      player.play(ep);
    }
  }
}
