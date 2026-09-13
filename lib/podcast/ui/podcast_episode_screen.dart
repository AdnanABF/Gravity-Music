// podcast/ui/podcast_episode_screen.dart
//
// The episode detail page (spec §13): artwork, title, show, description,
// published date, duration, progress, and the full action set. Search rows
// arrive without a description or duration, so the page hydrates itself from
// the episode's own YT Music page on open.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/theme/glass.dart';
import '../../ui/theme/motion.dart';
import '../controllers/podcast_library_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../models/podcast_episode.dart';
import '../services/podcast_service.dart';
import 'podcast_format.dart';
import 'podcast_show_screen.dart';
import 'widgets/podcast_artwork_image.dart';
import 'widgets/podcast_mini_player.dart';

class PodcastEpisodeScreen extends StatefulWidget {
  final PodcastEpisode episode;
  const PodcastEpisodeScreen({super.key, required this.episode});

  @override
  State<PodcastEpisodeScreen> createState() => _PodcastEpisodeScreenState();
}

class _PodcastEpisodeScreenState extends State<PodcastEpisodeScreen> {
  late PodcastEpisode _episode = widget.episode;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final full = await PodcastService.hydrate(_episode);
    if (mounted && full != _episode) setState(() => _episode = full);
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PodcastPlayerController>();
    final library = Get.find<PodcastLibraryController>();
    final width = MediaQuery.sizeOf(context).width;
    final artWidth =
        (width - AppSpacing.screenMargin * 2).clamp(200.0, 420.0).toDouble();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: ScreenWithPodcastMiniPlayer(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.canvas,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: const AppBackButton(),
              title: Text('Episode', style: AppText.navTitle()),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenMargin),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: PodcastArtworkImage(
                        url: _episode.displayArtwork,
                        width: artWidth,
                        natural: true,
                        radius: AppRadius.lg,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    if (_episode.showTitle.isNotEmpty)
                      Pressable(
                        onTap: () {
                          if (_episode.showId.isEmpty) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PodcastShowScreen(
                              showId: _episode.showId,
                              title: _episode.showTitle,
                              artwork: _episode.showArtwork,
                            ),
                          ));
                        },
                        pressedScale: 0.98,
                        child: Text(_episode.showTitle.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(color: AppColors.accent)),
                      ),
                    const SizedBox(height: 8),
                    Text(_episode.title, style: AppText.heading(size: 21)),
                    const SizedBox(height: 8),
                    Obx(() {
                      player.progressRevision.value;
                      final progress = player.progressFor(_episode.id);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            episodeStatusLine(_episode.duration, progress,
                                _episode.publishedAt, _episode.publishedLabel),
                            style: AppText.subtitle(size: 13),
                          ),
                          if (progress != null && progress.inProgress) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress.percent,
                                minHeight: 4,
                                backgroundColor:
                                    Colors.white.withOpacity(0.14),
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.accent),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                                '${fmtClock(progress.position)} / '
                                '${fmtClock(progress.duration)}'
                                '  ·  ${(progress.percent * 100).round()}% complete',
                                style: AppText.caption()),
                          ],
                        ],
                      );
                    }),
                    const SizedBox(height: AppSpacing.gutter),

                    // ── Primary + secondary actions ────────────────────
                    Obx(() {
                      player.progressRevision.value;
                      final progress = player.progressFor(_episode.id);
                      final resuming =
                          progress != null && progress.inProgress;
                      return Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              icon: Icons.play_arrow_rounded,
                              label: resuming
                                  ? 'Resume · ${fmtRemaining(progress.remaining)}'
                                  : 'Play episode',
                              onTap: () => player.play(_episode),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Obx(() {
                            library.saved.length;
                            final saved = library.isSaved(_episode.id);
                            return GlassIconButton(
                              icon: saved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              iconColor:
                                  saved ? AppColors.accent : Colors.white,
                              onTap: () => library.toggleSave(_episode),
                            );
                          }),
                          const SizedBox(width: 8),
                          Obx(() {
                            final busy = library.isDownloading(_episode.id);
                            final done = library.isDownloaded(_episode.id);
                            if (busy) {
                              return SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: library.downloading[_episode.id],
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return GlassIconButton(
                              icon: done
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              iconColor:
                                  done ? AppColors.accent : Colors.white,
                              onTap: () async {
                                if (done) {
                                  await library.removeDownload(_episode.id);
                                  return;
                                }
                                final err = await library.download(_episode);
                                if (err != null) {
                                  Get.snackbar('Download failed', err,
                                      snackPosition: SnackPosition.BOTTOM,
                                      backgroundColor: AppColors.card,
                                      colorText: AppColors.white);
                                }
                              },
                            );
                          }),
                          const SizedBox(width: 8),
                          Obx(() {
                            player.progressRevision.value;
                            final done = player
                                    .progressFor(_episode.id)
                                    ?.completed ??
                                false;
                            return GlassIconButton(
                              icon: done
                                  ? Icons.check_circle_rounded
                                  : Icons.check_circle_outline_rounded,
                              iconColor:
                                  done ? AppColors.accent : Colors.white,
                              onTap: () =>
                                  player.markPlayed(_episode, played: !done),
                            );
                          }),
                        ],
                      );
                    }),

                    const SizedBox(height: AppSpacing.stackMd),
                    if (_episode.description.isNotEmpty) ...[
                      Text('Episode notes', style: AppText.heading(size: 17)),
                      const SizedBox(height: 10),
                      SelectableText(
                        _episode.description,
                        style: AppText.subtitle(size: 13.5).copyWith(
                            height: 1.5, color: AppColors.textSecondaryHi),
                      ),
                    ],
                    const SizedBox(height: 140),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
