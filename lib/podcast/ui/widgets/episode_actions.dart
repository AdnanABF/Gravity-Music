// podcast/ui/widgets/episode_actions.dart
//
// The long-press / "…" sheet for an episode: the podcast-specific actions from
// spec §12 — Play, Resume, Save, Download, Mark as played. Distinct from the
// music track-actions sheet (Play next / Add to queue / Add to playlist),
// which stays exactly as it is.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme/glass.dart';
import '../../controllers/podcast_library_controller.dart';
import '../../controllers/podcast_player_controller.dart';
import '../../models/podcast_episode.dart';
import '../podcast_format.dart';
import '../podcast_show_screen.dart';

void showEpisodeActions(BuildContext context, PodcastEpisode episode) {
  final player = Get.find<PodcastPlayerController>();
  final library = Get.find<PodcastLibraryController>();
  final progress = player.progressFor(episode.id);
  final resuming = progress != null && progress.inProgress;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => GlassContainer(
      radius: AppRadius.xl,
      fill: AppColors.card.withOpacity(0.78),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: 10),
            ListTile(
              title: Text(episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title(size: 14.5)),
              subtitle: Text(
                episodeStatusLine(episode.duration, progress,
                    episode.publishedAt, episode.publishedLabel),
                style: AppText.subtitle(size: 12.5),
              ),
            ),
            const Divider(height: 8, color: AppColors.glassBorder),

            if (resuming)
              _Action(
                icon: Icons.play_arrow_rounded,
                label: 'Resume · ${fmtRemaining(progress.remaining)}',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  player.resume(episode);
                },
              ),
            _Action(
              icon: resuming
                  ? Icons.restart_alt_rounded
                  : Icons.play_arrow_rounded,
              label: resuming ? 'Play from start' : 'Play',
              onTap: () {
                Navigator.pop(sheetCtx);
                player.play(episode, fromStart: resuming);
              },
            ),

            Obx(() {
              library.saved.length; // observe
              final saved = library.isSaved(episode.id);
              return _Action(
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: saved ? 'Remove from Saved' : 'Save episode',
                onTap: () {
                  library.toggleSave(episode);
                  Navigator.pop(sheetCtx);
                },
              );
            }),

            Obx(() {
              final downloading = library.isDownloading(episode.id);
              final done = library.isDownloaded(episode.id);
              return _Action(
                icon: downloading
                    ? Icons.stop_circle_outlined
                    : (done
                        ? Icons.delete_outline_rounded
                        : Icons.download_rounded),
                label: downloading
                    ? 'Cancel download'
                    : (done ? 'Remove download' : 'Download'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  if (downloading) {
                    library.cancelDownload(episode.id);
                  } else if (done) {
                    await library.removeDownload(episode.id);
                  } else {
                    final err = await library.download(episode);
                    if (err != null) {
                      Get.snackbar('Download failed', err,
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: AppColors.card,
                          colorText: AppColors.white);
                    }
                  }
                },
              );
            }),

            Obx(() {
              player.progressRevision.value;
              final done = player.progressFor(episode.id)?.completed ?? false;
              return _Action(
                icon: done
                    ? Icons.remove_done_rounded
                    : Icons.check_circle_outline_rounded,
                label: done ? 'Mark as unplayed' : 'Mark as played',
                onTap: () {
                  player.markPlayed(episode, played: !done);
                  Navigator.pop(sheetCtx);
                },
              );
            }),

            if (episode.showId.isNotEmpty)
              _Action(
                icon: Icons.podcasts_rounded,
                label: 'Go to show',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PodcastShowScreen(
                        showId: episode.showId, title: episode.showTitle),
                  ));
                },
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Colors.white, size: 22),
        title: Text(label, style: AppText.title(size: 14.5)),
        onTap: onTap,
      );
}
