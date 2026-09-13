// podcast/ui/widgets/podcast_mini_player.dart
//
// The floating bar shown while an episode is loaded. Separate from the music
// MiniPlayer (which is untouched) because the transport differs: podcasts get
// −15s / play / +30s, not previous / play / next, and the bar shows time
// remaining rather than a track's elapsed position.
//
// [ModeAwareMiniPlayer] at the bottom is what the shell mounts: it renders
// this bar whenever the ENGINE is on a podcast episode, and the untouched
// music mini-player otherwise — so an episode can never be drawn through
// music chrome, even if the user switches to Music Mode mid-episode.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme/glass.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/widgets/mini_player.dart';
import '../../controllers/podcast_player_controller.dart';
import '../podcast_format.dart';
import '../podcast_player_screen.dart';
import 'podcast_artwork_image.dart';

class PodcastMiniPlayer extends StatelessWidget {
  const PodcastMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PodcastPlayerController>();

    return Obx(() {
      final episode = player.currentEpisode.value;
      if (episode == null) return const SizedBox.shrink();

      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
        child: Pressable(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PodcastPlayerScreen())),
          pressedScale: 0.99,
          child: GlassContainer(
            radius: AppRadius.xl,
            blur: 24,
            shadow: kGlassShadow,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                  child: Row(
                    children: [
                      PodcastArtworkImage(
                        url: episode.displayArtwork,
                        width: 64,
                        ratio: 16 / 9,
                        radius: AppRadius.sm,
                        backdrop: false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(episode.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.title(size: 13.5)),
                            const SizedBox(height: 2),
                            Obx(() {
                              final total = player.duration.value;
                              final left = total - player.position.value;
                              return Text(
                                total > Duration.zero
                                    ? fmtRemaining(left)
                                    : episode.showTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.subtitle(size: 11.5),
                              );
                            }),
                          ],
                        ),
                      ),
                      _MiniButton(
                        icon: Icons.replay_10_rounded,
                        onTap: player.skipBack,
                      ),
                      Obx(() {
                        final loading = player.isLoading.value;
                        final playing = player.isPlaying.value;
                        return _MiniButton(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 40,
                          iconSize: 26,
                          busy: loading,
                          onTap: player.togglePlayPause,
                        );
                      }),
                      _MiniButton(
                        icon: Icons.forward_30_rounded,
                        onTap: player.skipForward,
                      ),
                    ],
                  ),
                ),
                // A hairline progress line along the bottom of the glass.
                Obx(() {
                  final total = player.duration.value.inMilliseconds;
                  final pos = player.position.value.inMilliseconds;
                  final value = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0);
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(AppRadius.xl)),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 2,
                      backgroundColor: Colors.white.withOpacity(0.10),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool busy;

  const _MiniButton({
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.iconSize = 22,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: SizedBox(
          width: size,
          height: size,
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : Icon(icon, size: iconSize, color: Colors.white),
        ),
      );
}

/// Picks the right mini-player for whatever the shared engine is playing.
///
/// This is the one place the two domains meet visually, and it resolves the
/// meeting by DELEGATION: a podcast episode gets the podcast bar, anything
/// else gets the existing music [MiniPlayer], unmodified.
class ModeAwareMiniPlayer extends StatelessWidget {
  const ModeAwareMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = podcastPlayerOrNull;
    if (player == null) return const MiniPlayer();
    return Obx(() => player.currentEpisode.value != null
        ? const PodcastMiniPlayer()
        : const MiniPlayer());
  }
}

/// Re-docks the podcast mini-player at the bottom of a PUSHED route.
///
/// The shell's dock is covered by pushed routes (show page, episode page), so
/// detail screens wrap their body in this for continuity — the podcast
/// equivalent of music's ScreenWithMiniPlayer, which stays untouched.
class ScreenWithPodcastMiniPlayer extends StatelessWidget {
  final Widget child;
  const ScreenWithPodcastMiniPlayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final player = podcastPlayerOrNull;
    if (player == null) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Obx(() => player.currentEpisode.value == null
                  ? const SizedBox.shrink()
                  : const PodcastMiniPlayer()),
            ),
          ),
        ),
      ],
    );
  }
}

/// The DESKTOP bottom dock for podcasts: the podcast bar sized and coloured to
/// sit exactly where the music NowPlayingBar does (84px, canvas-backed).
///
/// Mounted by BOTH shells. In Podcast Mode it is the dock; in Music Mode the
/// shell layers it over the music bar, so an episode is never rendered through
/// music chrome with prev/next controls that do nothing for it. Renders
/// nothing at all when no episode is loaded, leaving the music bar untouched.
class PodcastDesktopDock extends StatelessWidget {
  const PodcastDesktopDock({super.key});

  /// Matches NowPlayingBar's fixed height so the overlay covers it exactly.
  static const double height = 84;

  @override
  Widget build(BuildContext context) {
    final player = podcastPlayerOrNull;
    if (player == null) return const SizedBox.shrink();
    return Obx(() => player.currentEpisode.value == null
        ? const SizedBox.shrink()
        // Material: Music Mode layers this dock over its Scaffold from
        // outside it, so without one every Text inherits no style and renders
        // with Flutter's yellow double-underline fallback.
        : Material(
            color: AppColors.canvas,
            child: Container(
              height: height,
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter, 4, AppSpacing.gutter, 10),
              child: const PodcastMiniPlayer(),
            ),
          ));
  }
}
