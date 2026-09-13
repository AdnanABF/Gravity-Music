// podcast/ui/widgets/mode_switch.dart
//
// The Music ⇄ Podcasts switch. Lives entirely in podcast code; the shells just
// place it, so no music widget knows it exists.
//
// There is deliberately ONE control, not two. An earlier pass had a segmented
// control in the podcast sidebar, a pill in the podcast home header, and a
// different pill in the music dock — three looks in three places, which read
// as three unrelated features. This is now the only switch, mounted in the
// same spot in both modes: above the mini-player on mobile, at the foot of the
// sidebar on desktop.
//
// It has to live in the SHELL rather than in a screen header, because Music
// Mode's screens are frozen — there is no music header this could be added to
// without editing music UI. Sitting in the floating dock layer is also where
// it belongs conceptually: it is chrome, like the mini-player it sits above.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme/glass.dart';
import '../../controllers/podcast_mode_controller.dart';

/// One tap flips to the other mode; the label names the mode you'd land in.
///
/// Rendered as real glass (blur + hairline border + the dock's shadow) so it
/// reads as part of the floating chrome rather than a stray chip resting on
/// the artwork behind it.
class ModeSwitchPill extends StatelessWidget {
  /// Icon-only, for the collapsed desktop rail.
  final bool compact;

  const ModeSwitchPill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final mode = Get.find<PodcastModeController>();

    return Obx(() {
      if (!mode.switchEnabled.value) return const SizedBox.shrink();
      final toMusic = mode.isPodcast;
      final icon = toMusic ? Icons.music_note_rounded : Icons.podcasts_rounded;
      final label = toMusic ? 'Music' : 'Podcasts';

      // Material ancestor of its own: in Music Mode the shell places this in
      // a Stack OUTSIDE the music Scaffold, where Text has no DefaultTextStyle
      // and Flutter paints its yellow double-underline fallback.
      return Material(
        type: MaterialType.transparency,
        child: Semantics(
          button: true,
          label: 'Switch to $label',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AppHaptics.selection();
              mode.toggle();
            },
            child: GlassContainer(
              radius: AppRadius.pill,
              blur: 24,
              shadow: kGlassShadow,
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: Colors.white),
                  if (!compact) ...[
                    const SizedBox(width: 7),
                    Text(label,
                        style: AppText.button()
                            .copyWith(letterSpacing: 0, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The pill as it sits in the mobile dock, above the mini-player — spacing
/// included, so that when the switch is turned off in Settings the dock
/// collapses back to exactly its pre-Podcasts height instead of keeping an
/// empty gap where the pill was.
class ModeSwitchDockSlot extends StatelessWidget {
  const ModeSwitchDockSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = Get.find<PodcastModeController>();
    return Obx(() => !mode.switchEnabled.value
        ? const SizedBox.shrink()
        : const Padding(
            padding: EdgeInsets.only(right: AppSpacing.screenMargin, bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: ModeSwitchPill(),
            ),
          ));
  }
}
