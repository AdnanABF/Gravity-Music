// podcast/ui/podcast_home_screen.dart
//
// Podcast Home (spec §9). Built around consumption, not catalogue:
//
//   Continue Listening   the first thing a podcast listener wants
//   New from your shows  the second
//   Picked for you       podcast-specific recommendations, with reasons
//   Recommended shows    "Because you listened to …"
//   Discover             topic shelves from YT Music's podcast feed
//
// Nothing here reads music state — no searchHistory, no mixes, no liked songs.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/shell/responsive.dart';
import '../../ui/ui_helpers.dart';
import '../../ui/widgets/common_widgets.dart';
import '../controllers/podcast_home_controller.dart';
import '../controllers/podcast_library_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'podcast_episode_screen.dart';
import 'podcast_shell.dart';
import 'podcast_show_screen.dart';
import 'widgets/episode_actions.dart';
import 'widgets/episode_tile.dart';
import 'widgets/show_card.dart';

class PodcastHomeScreen extends StatelessWidget {
  const PodcastHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Get.put(PodcastHomeController());
    final player = Get.find<PodcastPlayerController>();
    final library = Get.find<PodcastLibraryController>();

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: () => home.load(forceRefresh: true),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 124, // matches the music home header
            backgroundColor: AppColors.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            // No mode switch here: it lives in the dock, in the same slot in
            // both modes (see ModeSwitchPill). The expanded band carries the
            // greeting instead, mirroring the music home header exactly.
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.screenMargin, bottom: 14),
              expandedTitleScale: 1.7,
              title: Text('Podcasts', style: AppText.navTitle()),
              background: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: AppSpacing.screenMargin, bottom: 46),
                    child: Text(greetingForNow(),
                        style: AppText.subtitle(size: 15)),
                  ),
                ),
              ),
            ),
          ),

          // ── Continue Listening ───────────────────────────────────────
          SliverToBoxAdapter(child: Obx(() {
            player.progressRevision.value; // refresh bars in place
            final items = home.continueListening;
            if (items.isEmpty) return const SizedBox.shrink();
            return _Carousel(
              title: 'Continue Listening',
              height: ContinueCard.heightFor(context, 230),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final entry = items[i];
                return ContinueCard(
                  episode: entry.episode,
                  progress: entry.progress,
                  onTap: () => _openEpisode(context, entry.episode),
                  onPlay: () => player.resume(entry.episode),
                );
              },
            );
          })),

          // ── New from your shows ──────────────────────────────────────
          SliverToBoxAdapter(child: Obx(() {
            final items = home.newEpisodes;
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'New From Your Shows'),
                ...items.take(5).map((e) => EpisodeTile(
                      episode: e,
                      showDescription: false,
                      onTap: () => _openEpisode(context, e),
                      onPlay: () => _playOrPause(player, e),
                      onMore: () => showEpisodeActions(context, e),
                    )),
                const SizedBox(height: AppSpacing.stackMd),
              ],
            );
          })),

          // ── Your shows ───────────────────────────────────────────────
          SliverToBoxAdapter(child: Obx(() {
            final shows = library.following;
            if (shows.isEmpty) return const SizedBox.shrink();
            return _Carousel(
              title: 'Your Shows',
              height: ShowCard.heightFor(context, 160),
              itemCount: shows.length,
              itemBuilder: (_, i) => ShowCard(
                show: shows[i],
                onTap: () => _openShow(context, shows[i]),
              ),
            );
          })),

          // ── Picked for you ───────────────────────────────────────────
          SliverToBoxAdapter(child: Obx(() {
            final items = home.picked;
            if (items.isEmpty) return const SizedBox.shrink();
            return _Carousel(
              title: 'Picked For You',
              height: ContinueCard.heightFor(context, 230),
              itemCount: items.length,
              itemBuilder: (_, i) => ContinueCard(
                episode: items[i],
                progress: null,
                onTap: () => _openEpisode(context, items[i]),
                onPlay: () => _playOrPause(player, items[i]),
              ),
            );
          })),

          // ── Recommended shows, grouped by reason ─────────────────────
          // Only once there is something to reason FROM. With no history and
          // nothing followed, every "recommendation" would be the same
          // editorial filler the Discover shelves below already carry, under a
          // heading that claims to know the listener's taste.
          SliverToBoxAdapter(child: Obx(() {
            final recs = home.recommended;
            final personalized = home.continueListening.isNotEmpty ||
                home.picked.isNotEmpty ||
                library.following.isNotEmpty;
            if (recs.isEmpty || !personalized) return const SizedBox.shrink();
            // Group by reason so the row header states WHY, rather than each
            // card carrying its own caption.
            final byReason = <String, List<PodcastShow>>{};
            for (final r in recs) {
              byReason.putIfAbsent(r.reason, () => []).add(r.show);
            }
            final groups = byReason.entries.take(3).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groups
                  .map((g) => _Carousel(
                        title: g.key,
                        height: ShowCard.heightFor(context, 160),
                        itemCount: g.value.length,
                        itemBuilder: (_, i) => ShowCard(
                          show: g.value[i],
                          onTap: () => _openShow(context, g.value[i]),
                        ),
                      ))
                  .toList(),
            );
          })),

          // ── Discover shelves ─────────────────────────────────────────
          // The catalogue's own topic rows, inline on Home. This is what a
          // brand-new listener actually sees — without it Home is one row of
          // shows and a screen of black, which is what the first build did.
          SliverToBoxAdapter(child: Obx(() {
            final shelves = home.shelves;
            if (shelves.isEmpty) return const SizedBox.shrink();
            final personalized = home.continueListening.isNotEmpty ||
                home.picked.isNotEmpty ||
                library.following.isNotEmpty;
            // Fewer rows once Home has personal content to lead with.
            final rows = shelves.take(personalized ? 3 : 8).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows.map((shelf) {
                if (shelf.shows.isNotEmpty) {
                  return _Carousel(
                    title: shelf.title,
                    height: ShowCard.heightFor(context, 160),
                    itemCount: shelf.shows.length,
                    itemBuilder: (_, i) => ShowCard(
                      show: shelf.shows[i],
                      onTap: () => _openShow(context, shelf.shows[i]),
                    ),
                  );
                }
                return _Carousel(
                  title: shelf.title,
                  height: ContinueCard.heightFor(context, 230),
                  itemCount: shelf.episodes.length,
                  itemBuilder: (_, i) => ContinueCard(
                    episode: shelf.episodes[i],
                    progress: null,
                    onTap: () => _openEpisode(context, shelf.episodes[i]),
                    onPlay: () => _playOrPause(player, shelf.episodes[i]),
                  ),
                );
              }).toList(),
            );
          })),

          // ── Loading / empty ──────────────────────────────────────────
          SliverToBoxAdapter(child: Obx(() {
            if (home.loading.value && home.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 80),
                child:
                    Center(child: CircularProgressIndicator(color: Colors.white)),
              );
            }
            if (!home.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 60),
              child: EmptyState(
                icon: Icons.podcasts_rounded,
                title: 'Find your first show',
                message:
                    'Search for a podcast or browse Discover — episodes you\n'
                    'start will show up here so you can pick up where you left off.',
                action: GlassPillButton(
                  icon: Icons.search_rounded,
                  label: 'Search podcasts',
                  onTap: () => PodcastShellNav.goToTab?.call(
                      PodcastShellNav.searchTabIndex),
                ),
              ),
            );
          })),

          SliverToBoxAdapter(
              child: SizedBox(height: bottomDockInset(context) + 24)),
        ],
      ),
    );
  }

  void _openEpisode(BuildContext context, PodcastEpisode e) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastEpisodeScreen(episode: e)));

  void _openShow(BuildContext context, PodcastShow s) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastShowScreen(
              showId: s.id, title: s.title, artwork: s.artwork)));

  void _playOrPause(PodcastPlayerController player, PodcastEpisode e) {
    if (player.isCurrent(e.id)) {
      player.togglePlayPause();
    } else {
      player.play(e);
    }
  }
}

class _Carousel extends StatelessWidget {
  final String title;
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _Carousel({
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenMargin),
              itemCount: itemCount,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.gutter),
              itemBuilder: itemBuilder,
            ),
          ),
          const SizedBox(height: AppSpacing.stackMd),
        ],
      );
}
