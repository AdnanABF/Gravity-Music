// podcast/ui/podcast_discover_screen.dart
//
// Discover: YT Music's own podcast landing feed, rendered as its topic
// shelves ("Popular shows", "Meditation", "Thrillers", …). This is also the
// topic index the recommender uses, so what the listener browses and what the
// recommender reasons about come from the same place.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/shell/responsive.dart';
import '../../ui/widgets/common_widgets.dart';
import '../controllers/podcast_home_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import 'podcast_episode_screen.dart';
import 'podcast_show_screen.dart';
import 'widgets/episode_tile.dart';
import 'widgets/show_card.dart';

class PodcastDiscoverScreen extends StatelessWidget {
  const PodcastDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Shares the home controller: Discover and Home are fed by the same
    // Discover fetch, so opening this tab costs nothing extra.
    final home = Get.put(PodcastHomeController());
    final player = Get.find<PodcastPlayerController>();

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: () => home.load(forceRefresh: true),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 106,
            backgroundColor: AppColors.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.screenMargin, bottom: 14),
              expandedTitleScale: 1.7,
              title: Text('Discover', style: AppText.navTitle()),
            ),
          ),
          Obx(() {
            final shelves = home.shelves;
            if (shelves.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: home.loading.value
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white))
                      : const EmptyState(
                          icon: Icons.explore_rounded,
                          title: 'Discover is offline',
                          message:
                              "We couldn't reach the podcast catalogue.\nPull to try again.",
                        ),
                ),
              );
            }
            return SliverList.builder(
              itemCount: shelves.length,
              itemBuilder: (_, i) {
                final shelf = shelves[i];
                if (shelf.shows.isNotEmpty) {
                  return _ShelfRow(
                    title: shelf.title,
                    height: ShowCard.heightFor(context, 160),
                    itemCount: shelf.shows.length,
                    itemBuilder: (_, j) => ShowCard(
                      show: shelf.shows[j],
                      onTap: () => _openShow(context, shelf.shows[j]),
                    ),
                  );
                }
                return _ShelfRow(
                  title: shelf.title,
                  height: ContinueCard.heightFor(context, 230),
                  itemCount: shelf.episodes.length,
                  itemBuilder: (_, j) => ContinueCard(
                    episode: shelf.episodes[j],
                    progress: null,
                    onTap: () => _openEpisode(context, shelf.episodes[j]),
                    onPlay: () => player.play(shelf.episodes[j]),
                  ),
                );
              },
            );
          }),
          SliverToBoxAdapter(
              child: SizedBox(height: bottomDockInset(context) + 24)),
        ],
      ),
    );
  }

  void _openShow(BuildContext context, PodcastShow s) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastShowScreen(
              showId: s.id, title: s.title, artwork: s.artwork)));

  void _openEpisode(BuildContext context, PodcastEpisode e) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastEpisodeScreen(episode: e)));
}

class _ShelfRow extends StatelessWidget {
  final String title;
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _ShelfRow({
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
