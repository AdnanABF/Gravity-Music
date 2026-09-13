// podcast/ui/podcast_search_screen.dart
//
// Podcast search (spec §4). A dedicated screen, not the music search screen
// with conditionals: results are grouped into SHOWS, CREATORS and EPISODES,
// which the music screen has no notion of, and the rows are podcast rows with
// 16:9 art and progress state.
//
// The music SearchScreen and its SearchUiController are untouched and remain
// mounted in the music shell with their own text field and focus node.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/shell/responsive.dart';
import '../../ui/theme/glass.dart';
import '../../ui/widgets/common_widgets.dart';
import '../controllers/podcast_player_controller.dart';
import '../controllers/podcast_search_controller.dart';
import '../models/podcast_show.dart';
import '../services/podcast_search_service.dart';
import 'podcast_episode_screen.dart';
import 'podcast_show_screen.dart';
import 'widgets/episode_actions.dart';
import 'widgets/episode_tile.dart';
import 'widgets/podcast_artwork_image.dart';
import 'widgets/show_card.dart';

/// Topic chips — each runs a real podcast search, the same way music's genre
/// tiles run a real song search.
const _topics = [
  'True crime',
  'Business',
  'Comedy',
  'Health',
  'Technology',
  'History',
  'Science',
  'Sports',
  'News',
  'Meditation',
];

class PodcastSearchScreen extends StatelessWidget {
  const PodcastSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = Get.put(PodcastSearchController());
    final player = Get.find<PodcastPlayerController>();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenMargin, 16,
                AppSpacing.screenMargin, AppSpacing.gutter),
            child: Row(
              children: [
                Expanded(
                    child: Text('Search', style: AppText.heading(size: 32))),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
            child: GlassContainer(
              radius: AppRadius.pill,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      color: AppColors.textTertiary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sc.textController,
                      focusNode: sc.focusNode,
                      onChanged: sc.onChanged,
                      textInputAction: TextInputAction.search,
                      style: AppText.title(size: 15),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                        border: InputBorder.none,
                        hintText: 'Shows, episodes, or creators',
                        hintStyle: AppText.subtitle(size: 15),
                      ),
                    ),
                  ),
                  Obx(() => sc.query.value.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: sc.clear,
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textTertiary, size: 20),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gutter),
          Expanded(
            child: Obx(() {
              if (sc.query.value.trim().isEmpty) {
                return _TopicGrid(onTap: sc.runQuery);
              }
              final results = sc.results.value;
              if (sc.loading.value && results.isEmpty) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              if (results.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No podcasts found',
                  message: 'Try a show name, a host, or a topic.',
                );
              }
              return _Results(results: results, player: player);
            }),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final PodcastSearchResults results;
  final PodcastPlayerController player;

  const _Results({required this.results, required this.player});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (results.shows.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Shows')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: ShowCard.heightFor(context, 160),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenMargin),
                itemCount: results.shows.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.gutter),
                itemBuilder: (_, i) => ShowCard(
                  show: results.shows[i],
                  onTap: () => _openShow(context, results.shows[i]),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.stackMd)),
        ],

        if (results.creators.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Creators')),
          SliverList.builder(
            itemCount: results.creators.length,
            itemBuilder: (_, i) {
              final c = results.creators[i];
              return _CreatorRow(
                creator: c,
                onTapShow: (s) => _openShow(context, s),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.stackMd)),
        ],

        if (results.episodes.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Episodes')),
          SliverList.separated(
            itemCount: results.episodes.length,
            separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: AppSpacing.screenMargin,
                endIndent: AppSpacing.screenMargin,
                color: AppColors.borderSoft),
            itemBuilder: (_, i) {
              final e = results.episodes[i];
              return EpisodeTile(
                episode: e,
                showDescription: false,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PodcastEpisodeScreen(episode: e))),
                onPlay: () => player.isCurrent(e.id)
                    ? player.togglePlayPause()
                    : player.play(e),
                onMore: () => showEpisodeActions(context, e),
              );
            },
          ),
        ],

        SliverToBoxAdapter(
            child: SizedBox(height: bottomDockInset(context) + 24)),
      ],
    );
  }

  void _openShow(BuildContext context, PodcastShow s) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastShowScreen(
              showId: s.id, title: s.title, artwork: s.artwork)));
}

/// A creator and their shows — the third result kind. Renders as a labelled
/// strip so one publisher's catalogue reads as a group.
class _CreatorRow extends StatelessWidget {
  final PodcastCreator creator;
  final void Function(PodcastShow) onTapShow;

  const _CreatorRow({required this.creator, required this.onTapShow});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenMargin, vertical: 6),
              child: Row(
                children: [
                  PodcastArtworkImage(
                    url: creator.artwork,
                    width: 34,
                    ratio: 1,
                    radius: AppRadius.pill,
                    backdrop: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(creator.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(size: 14.5)),
                  ),
                  Text('${creator.shows.length} shows',
                      style: AppText.caption()),
                ],
              ),
            ),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenMargin),
                itemCount: creator.shows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                  width: 96,
                  child: GestureDetector(
                    onTap: () => onTapShow(creator.shows[i]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PodcastArtworkImage(
                          url: creator.shows[i].artwork,
                          width: 96,
                          ratio: 1,
                          radius: AppRadius.md,
                          backdrop: false,
                        ),
                        const SizedBox(height: 6),
                        Text(creator.shows[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle(size: 11.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Idle state: topic chips that run real searches.
class _TopicGrid extends StatelessWidget {
  final void Function(String) onTap;
  const _TopicGrid({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.screenMargin, 4,
          AppSpacing.screenMargin, bottomDockInset(context) + 24),
      children: [
        Text('Browse topics', style: AppText.heading(size: 20)),
        const SizedBox(height: AppSpacing.gutter),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _topics
              .map((t) => GlassPillButton(
                    label: t,
                    icon: Icons.tag_rounded,
                    onTap: () => onTap(t),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
