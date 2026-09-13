// podcast/ui/widgets/episode_tile.dart
//
// The podcast list row. Not TrackTile: a track row is artwork + title + artist
// + duration, whereas an episode row has to carry a show name, a publish date,
// a progress bar, and a description snippet — and its artwork is 16:9, not
// square. Music's TrackTile is untouched and still used throughout Music Mode.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme/motion.dart';
import '../../controllers/podcast_player_controller.dart';
import '../../models/episode_progress.dart';
import '../../models/podcast_episode.dart';
import '../podcast_format.dart';
import 'podcast_artwork_image.dart';

class EpisodeTile extends StatelessWidget {
  final PodcastEpisode episode;

  /// Tapping the row (usually: open the episode page).
  final VoidCallback onTap;

  /// Tapping the play affordance.
  final VoidCallback onPlay;

  final VoidCallback? onMore;

  /// Show the series name above the title. Off on a show page, where every
  /// row belongs to the same series.
  final bool showSeries;

  /// Include the description snippet. Off in dense lists.
  final bool showDescription;

  const EpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    required this.onPlay,
    this.onMore,
    this.showSeries = true,
    this.showDescription = true,
  });

  @override
  Widget build(BuildContext context) {
    // Get.find, not the nullable accessor: every Obx below must read an
    // observable, and `player?.x.value` reads nothing when player is null —
    // which throws ObxError and paints a blank grey box in release builds.
    // EpisodeTile only ever renders inside Podcast Mode, where the controller
    // is registered, so a hard find is both correct and safer.
    final player = Get.find<PodcastPlayerController>();

    return Pressable(
      onTap: onTap,
      onLongPress: onMore,
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenMargin, 12, AppSpacing.screenMargin, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 16:9 art, never cropped to a square.
                PodcastArtworkImage(
                  url: episode.displayArtwork,
                  width: 108,
                  ratio: 16 / 9,
                  radius: AppRadius.md,
                  backdrop: false,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSeries && episode.showTitle.isNotEmpty) ...[
                        Text(
                          episode.showTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                              color: AppColors.textTertiary),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(size: 14.5),
                      ),
                      const SizedBox(height: 5),
                      // The status line re-reads progress whenever the player
                      // writes a new position, so a row updates in place.
                      Obx(() {
                        player.progressRevision.value;
                        final progress = player.progressFor(episode.id);
                        return Text(
                          episodeStatusLine(
                            _length(progress),
                            progress,
                            episode.publishedAt,
                            episode.publishedLabel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle(size: 12),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
            if (showDescription && episode.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                oneLine(episode.description),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle(size: 12.5)
                    .copyWith(height: 1.35, color: AppColors.textSecondaryHi),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _PlayAffordance(episode: episode, onPlay: onPlay),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() {
                    player.progressRevision.value;
                    final progress = player.progressFor(episode.id);
                    if (progress == null || !progress.inProgress) {
                      return const SizedBox.shrink();
                    }
                    return _ProgressBar(value: progress.percent);
                  }),
                ),
                if (onMore != null)
                  IconButton(
                    onPressed: onMore,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: AppColors.textTertiary, size: 20),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Duration _length(EpisodeProgress? p) =>
      episode.duration > Duration.zero
          ? episode.duration
          : (p?.duration ?? Duration.zero);
}

/// The pill that starts (or resumes) the episode, and shows a pause glyph
/// while this episode is the one playing.
class _PlayAffordance extends StatelessWidget {
  final PodcastEpisode episode;
  final VoidCallback onPlay;

  const _PlayAffordance({required this.episode, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PodcastPlayerController>();
    return Obx(() {
      player.progressRevision.value;
      final isCurrent = player.currentEpisode.value?.id == episode.id;
      final playing = isCurrent && player.isPlaying.value;
      final progress = player.progressFor(episode.id);
      final resuming = progress != null && progress.inProgress;

      final label = playing
          ? 'Playing'
          : (resuming ? fmtRemaining(progress.remaining) : _lengthLabel());

      return Pressable(
        onTap: onPlay,
        pressedScale: 0.94,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.glassBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                playing
                    ? Icons.pause_rounded
                    : (resuming
                        ? Icons.play_arrow_rounded
                        : Icons.play_arrow_rounded),
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(label,
                  style: AppText.button(color: AppColors.textPrimary)
                      .copyWith(letterSpacing: 0)),
            ],
          ),
        ),
      );
    });
  }

  String _lengthLabel() {
    final d = episode.duration;
    return d > Duration.zero ? fmtEpisodeLength(d) : 'Play';
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 3,
          backgroundColor: Colors.white.withOpacity(0.14),
          valueColor: const AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
}

/// Compact variant for the Continue Listening carousel: artwork on top, a
/// progress bar across its base, title and remaining time beneath.
class ContinueCard extends StatelessWidget {
  final PodcastEpisode episode;

  /// Null for an episode that hasn't been started (the "Picked For You" row),
  /// which renders the same card without a progress bar.
  final EpisodeProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final double width;

  const ContinueCard({
    super.key,
    required this.episode,
    required this.progress,
    required this.onTap,
    required this.onPlay,
    this.width = 230,
  });

  static const double _titleSize = 13.5;
  static const double _captionSize = 11.5;
  static const double _lineHeight = 1.3;

  /// Height a [ContinueCard] of [width] needs at the current text scale.
  /// Artwork is 16:9 here, not square, so the height is NOT the width.
  static double heightFor(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(double fontSize) => scaler.scale(fontSize) * _lineHeight;
    return width * 9 / 16 +
        AppSpacing.stackSm +
        line(_titleSize) * 2 +
        3 +
        line(_captionSize) +
        2;
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                PodcastArtworkImage(
                  url: episode.displayArtwork,
                  width: width,
                  ratio: 16 / 9,
                  radius: AppRadius.lg,
                  backdrop: false,
                ),
                if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(AppRadius.lg)),
                    child: LinearProgressIndicator(
                      value: progress!.percent,
                      minHeight: 4,
                      backgroundColor: Colors.black.withOpacity(0.55),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 12,
                  child: Pressable(
                    onTap: onPlay,
                    pressedScale: 0.9,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.glassBorder, width: 1),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackSm),
            // Same discipline as ShowCard: the caption is flexible and clipped
            // so a two-line episode title can never paint overflow stripes,
            // and [heightFor] tells shelves exactly how tall to be.
            Flexible(
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(size: _titleSize)
                            .copyWith(height: _lineHeight)),
                    const SizedBox(height: 3),
                    Text(
                      '${episode.showTitle.isEmpty ? '' : '${episode.showTitle} · '}'
                      '${progress != null ? fmtRemaining(progress!.remaining) : fmtEpisodeLength(episode.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle(size: _captionSize)
                          .copyWith(height: _lineHeight),
                    ),
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
