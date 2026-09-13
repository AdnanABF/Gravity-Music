// podcast/ui/widgets/show_card.dart
//
// Show cards and rows. Kept apart from the music ArtCard/TrackTile because a
// show carries a creator line and a follow state, and its art must keep its
// own proportions rather than being forced square.

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme/motion.dart';
import '../../models/podcast_show.dart';
import 'podcast_artwork_image.dart';

/// Carousel / grid card for a show.
///
/// Podcast titles are long — "Smosh Reads Reddit Stories", "The Joe Rogan
/// Experience" — so the caption routinely runs to two lines where an album
/// title fits on one. Two things keep that from overflowing the row:
///
///  • [heightFor] gives callers the exact height a card needs, INCLUDING the
///    viewer's text-scale setting, so a shelf is never sized by a guess; and
///  • the caption is [Flexible] + clipped, so if a row is still short (a very
///    large accessibility text scale, say) the text truncates instead of
///    painting the debug overflow stripes.
class ShowCard extends StatelessWidget {
  final PodcastShow show;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;

  /// Optional line explaining WHY this show is being suggested.
  final String? reason;

  const ShowCard({
    super.key,
    required this.show,
    required this.onTap,
    this.onLongPress,
    this.size = 160,
    this.reason,
  });

  static const double _titleSize = 13.5;
  static const double _authorSize = 11.5;
  static const double _lineHeight = 1.3;

  /// Height a [ShowCard] of [size] needs, honouring the current text scale.
  /// Horizontal lists must use this for their `SizedBox` height.
  static double heightFor(BuildContext context, double size,
      {bool withAuthor = true, bool withReason = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(double fontSize) => scaler.scale(fontSize) * _lineHeight;
    return size +
        AppSpacing.stackSm +
        line(_titleSize) * 2 + // titles wrap to two lines
        (withAuthor ? 2 + line(_authorSize) : 0) +
        (withReason ? 3 + line(11) : 0) +
        2; // hairline slack for rounding
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PodcastArtworkImage(
              url: show.artwork,
              fallbackUrl: show.avatar,
              width: size,
              ratio: 1,
              radius: AppRadius.lg,
            ),
            const SizedBox(height: AppSpacing.stackSm),
            Flexible(
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(show.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(size: _titleSize)
                            .copyWith(height: _lineHeight)),
                    if (show.author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(show.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle(size: _authorSize)
                              .copyWith(height: _lineHeight)),
                    ],
                    if (reason != null && reason!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(reason!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption(color: AppColors.textTertiary)
                              .copyWith(height: _lineHeight)),
                    ],
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

/// Full-width row for a show, used in search results and the library list.
class ShowTile extends StatelessWidget {
  final PodcastShow show;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitleOverride;

  const ShowTile({
    super.key,
    required this.show,
    required this.onTap,
    this.trailing,
    this.subtitleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = subtitleOverride ??
        (show.author.isNotEmpty ? show.author : 'Podcast');
    return Pressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin, vertical: 9),
        child: Row(
          children: [
            PodcastArtworkImage(
              url: show.artwork,
              fallbackUrl: show.avatar,
              width: 58,
              ratio: 1,
              radius: AppRadius.md,
              backdrop: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.trackTitle(size: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle(size: 12.5)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// The follow toggle, shown on the show page and in library rows.
class FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  final bool compact;

  const FollowButton({
    super.key,
    required this.following,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = following ? 'Following' : 'Follow';
    return Pressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
        height: compact ? 32 : 38,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: following ? AppColors.glassFill : AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: following ? AppColors.glassBorder : Colors.transparent,
              width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              following ? Icons.check_rounded : Icons.add_rounded,
              size: compact ? 15 : 17,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: AppText.button().copyWith(
                    letterSpacing: 0, fontSize: compact ? 12 : 13)),
          ],
        ),
      ),
    );
  }
}
