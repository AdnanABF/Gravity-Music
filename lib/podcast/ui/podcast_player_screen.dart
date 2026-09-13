// podcast/ui/podcast_player_screen.dart
//
// The full-screen podcast player. Built around the way an episode is actually
// listened to, which is not how a song is:
//
//   • the primary transport is −15s / play / +30s, because the thing you do
//     most in a two-hour episode is jump over an ad or back over a sentence
//   • the scrubber is coarse and the clock shows time remaining, since "42
//     minutes left" is the question a listener has
//   • speed is a first-class control, not a hidden setting
//   • the description is on the same screen, because it's where the links and
//     the guest's name live
//
// The music NowPlayingScreen is untouched and still handles every song.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/theme/glass.dart';
import '../../ui/theme/motion.dart';
import '../controllers/podcast_library_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../services/podcast_prefs.dart';
import 'podcast_format.dart';
import 'podcast_show_screen.dart';
import 'widgets/podcast_artwork_image.dart';

class PodcastPlayerScreen extends StatelessWidget {
  const PodcastPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PodcastPlayerController>();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Obx(() {
        final episode = player.currentEpisode.value;
        if (episode == null) {
          // The episode was dismissed while this screen was open.
          return const Center(
            child: Text('Nothing playing',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }

        final width = MediaQuery.sizeOf(context).width;
        final artWidth = (width - AppSpacing.screenMargin * 2)
            .clamp(200.0, 420.0)
            .toDouble();

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenMargin, vertical: 8),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        iconSize: 26,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Text('NOW PLAYING',
                          style: AppText.label(
                              color: AppColors.textTertiary)),
                      const Spacer(),
                      GlassIconButton(
                        icon: Icons.close_rounded,
                        onTap: () {
                          player.dismiss();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── Artwork at its OWN aspect ratio ────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenMargin, vertical: 16),
                  child: Center(
                    child: PodcastArtworkImage(
                      url: episode.displayArtwork,
                      width: artWidth,
                      natural: true,
                      radius: AppRadius.xl,
                    ),
                  ),
                ),
              ),

              // ── Titles ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenMargin),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (episode.showTitle.isNotEmpty)
                        Pressable(
                          onTap: () {
                            if (episode.showId.isEmpty) return;
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PodcastShowScreen(
                                  showId: episode.showId,
                                  title: episode.showTitle),
                            ));
                          },
                          pressedScale: 0.98,
                          child: Text(episode.showTitle.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(
                                  color: AppColors.accent)),
                        ),
                      const SizedBox(height: 8),
                      Text(episode.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.heading(size: 21)),
                      const SizedBox(height: 6),
                      Text(
                          fmtPublished(
                              episode.publishedAt, episode.publishedLabel),
                          style: AppText.subtitle(size: 13)),
                    ],
                  ),
                ),
              ),

              // ── Scrubber ───────────────────────────────────────────────
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(child: _Scrubber(player: player)),

              // ── Transport ──────────────────────────────────────────────
              SliverToBoxAdapter(child: _Transport(player: player)),

              // ── Secondary actions ──────────────────────────────────────
              SliverToBoxAdapter(child: _ActionRow(player: player)),

              // ── Description ────────────────────────────────────────────
              if (episode.description.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenMargin,
                        AppSpacing.stackMd,
                        AppSpacing.screenMargin,
                        0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Episode notes',
                            style: AppText.heading(size: 17)),
                        const SizedBox(height: 10),
                        SelectableText(
                          episode.description,
                          style: AppText.subtitle(size: 13.5).copyWith(
                              height: 1.5,
                              color: AppColors.textSecondaryHi),
                        ),
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ),
        );
      }),
    );
  }
}

// ── Scrubber ────────────────────────────────────────────────────────────────

class _Scrubber extends StatefulWidget {
  final PodcastPlayerController player;
  const _Scrubber({required this.player});

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// Non-null while the user is dragging, so the thumb follows the finger
  /// instead of snapping back to the stream position between ticks.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return Obx(() {
      final total = p.duration.value;
      final totalMs = total.inMilliseconds.toDouble();
      final posMs = p.position.value.inMilliseconds
          .toDouble()
          .clamp(0.0, totalMs <= 0 ? 1.0 : totalMs);
      final value = _dragValue ?? posMs;

      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
        child: Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: Colors.white.withOpacity(0.16),
                thumbColor: Colors.white,
                overlayColor: AppColors.accent.withOpacity(0.15),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                min: 0,
                max: totalMs <= 0 ? 1.0 : totalMs,
                value: value.clamp(0.0, totalMs <= 0 ? 1.0 : totalMs),
                onChanged: totalMs <= 0
                    ? null
                    : (v) => setState(() => _dragValue = v),
                onChangeEnd: totalMs <= 0
                    ? null
                    : (v) {
                        p.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtClock(Duration(milliseconds: value.round())),
                      style: AppText.caption(
                          color: AppColors.textSecondaryHi)),
                  Text(
                      total > Duration.zero
                          ? '-${fmtClock(total - Duration(milliseconds: value.round()))}'
                          : '--:--',
                      style: AppText.caption(
                          color: AppColors.textSecondaryHi)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

class _Transport extends StatelessWidget {
  final PodcastPlayerController player;
  const _Transport({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Obx(() => _SkipButton(
                seconds: player.skipBackSeconds.value,
                back: true,
                onTap: player.skipBack,
              )),
          const SizedBox(width: 28),
          Obx(() {
            final playing = player.isPlaying.value;
            final loading = player.isLoading.value;
            return Pressable(
              onTap: player.togglePlayPause,
              pressedScale: 0.9,
              child: Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                        color: Colors.white),
              ),
            );
          }),
          const SizedBox(width: 28),
          Obx(() => _SkipButton(
                seconds: player.skipForwardSeconds.value,
                back: false,
                onTap: player.skipForward,
              )),
        ],
      ),
    );
  }
}

/// A skip control that states its own interval, so changing the preference is
/// immediately visible on the button.
class _SkipButton extends StatelessWidget {
  final int seconds;
  final bool back;
  final VoidCallback onTap;

  const _SkipButton({
    required this.seconds,
    required this.back,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(back ? Icons.rotate_left_rounded : Icons.rotate_right_rounded,
                  size: 44, color: Colors.white),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('$seconds',
                    style: AppText.caption(color: Colors.white)
                        .copyWith(fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
}

// ── Secondary actions ───────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final PodcastPlayerController player;
  const _ActionRow({required this.player});

  @override
  Widget build(BuildContext context) {
    final library = Get.find<PodcastLibraryController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenMargin, 12, AppSpacing.screenMargin, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Speed — a first-class control for podcasts.
          Obx(() => Pressable(
                onTap: () => _showSpeedSheet(context, player),
                pressedScale: 0.94,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border:
                        Border.all(color: AppColors.glassBorder, width: 1),
                  ),
                  child: Text(_speedLabel(player.speed.value),
                      style: AppText.button().copyWith(letterSpacing: 0)),
                ),
              )),
          Obx(() {
            final episode = player.currentEpisode.value;
            library.saved.length; // observe
            final saved =
                episode != null && library.isSaved(episode.id);
            return GlassIconButton(
              icon: saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              iconColor: saved ? AppColors.accent : Colors.white,
              onTap: () {
                if (episode == null) return;
                library.toggleSave(episode);
              },
            );
          }),
          Obx(() {
            final episode = player.currentEpisode.value;
            final downloading =
                episode != null && library.isDownloading(episode.id);
            final done = episode != null && library.isDownloaded(episode.id);
            if (downloading) {
              return SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: library.downloading[episode.id],
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
              iconColor: done ? AppColors.accent : Colors.white,
              onTap: () async {
                if (episode == null) return;
                if (done) {
                  await library.removeDownload(episode.id);
                  return;
                }
                final err = await library.download(episode);
                if (err != null) {
                  Get.snackbar('Download failed', err,
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: AppColors.card,
                      colorText: AppColors.white);
                }
              },
            );
          }),
          Obx(() {
            player.progressRevision.value;
            final episode = player.currentEpisode.value;
            final done =
                episode != null && (player.progressFor(episode.id)?.completed ?? false);
            return GlassIconButton(
              icon: done
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              iconColor: done ? AppColors.accent : Colors.white,
              onTap: () {
                if (episode == null) return;
                player.markPlayed(episode, played: !done);
              },
            );
          }),
          GlassIconButton(
            icon: Icons.tune_rounded,
            onTap: () => _showSkipSheet(context, player),
          ),
        ],
      ),
    );
  }
}

String _speedLabel(double v) =>
    '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString()}×';

/// Speed picker. Podcast-only: the value is stored in the podcast prefs and
/// the engine is reset to 1.0× the moment music becomes current.
void _showSpeedSheet(BuildContext context, PodcastPlayerController player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _Sheet(
      title: 'Playback speed',
      subtitle: 'Applies to podcasts only',
      children: PodcastPrefs.speeds
          .map((s) => Obx(() => ListTile(
                title: Text(_speedLabel(s), style: AppText.title(size: 15)),
                trailing: player.speed.value == s
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.accent)
                    : null,
                onTap: () {
                  player.setSpeed(s);
                  Navigator.pop(context);
                },
              )))
          .toList(),
    ),
  );
}

/// Skip-interval preferences.
void _showSkipSheet(BuildContext context, PodcastPlayerController player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _Sheet(
      title: 'Skip intervals',
      children: [
        Obx(() => _IntervalRow(
              label: 'Skip back',
              value: player.skipBackSeconds.value,
              onChanged: player.setSkipBack,
            )),
        Obx(() => _IntervalRow(
              label: 'Skip forward',
              value: player.skipForwardSeconds.value,
              onChanged: player.setSkipForward,
            )),
      ],
    ),
  );
}

class _IntervalRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _IntervalRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.title(size: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PodcastPrefs.skipOptions.map((s) {
                final selected = s == value;
                return Pressable(
                  onTap: () => onChanged(s),
                  pressedScale: 0.94,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : AppColors.glassFill,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                          color: AppColors.glassBorder, width: 1),
                    ),
                    child: Text('${s}s',
                        style: AppText.button().copyWith(letterSpacing: 0)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
}

class _Sheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _Sheet({required this.title, required this.children, this.subtitle});

  @override
  Widget build(BuildContext context) => GlassContainer(
        radius: AppRadius.xl,
        fill: AppColors.card.withOpacity(0.78),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 12),
              Text(title, style: AppText.heading(size: 17)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppText.subtitle(size: 12.5)),
              ],
              const SizedBox(height: 8),
              const Divider(height: 12, color: AppColors.glassBorder),
              ...children,
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}
