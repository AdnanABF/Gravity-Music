// podcast/ui/podcast_nav_bar.dart
//
// Podcast Mode's navigation (spec §14): Home · Discover · Search · Following ·
// Library. Independently implemented — it does NOT extend kNavDestinations or
// FloatingNavBar, so Music Mode's four-slot dock and its gliding pill are
// untouched and can change without dragging podcasts along.
//
// It follows the same visual language: a glass pill, a single indicator that
// glides between slots, an active icon that scales up with its label.

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/theme/glass.dart';
import '../../ui/theme/motion.dart';

class PodcastDestination {
  final IconData icon;
  final String label;
  const PodcastDestination(this.icon, this.label);
}

/// Four destinations. "Following" used to be its own tab AND the first chip
/// of Library — the same list reachable two ways, which read as two features.
/// It now lives only in Library, where saved/downloaded/history already are.
const List<PodcastDestination> kPodcastDestinations = [
  PodcastDestination(Icons.home_rounded, 'Home'),
  PodcastDestination(Icons.explore_rounded, 'Discover'),
  PodcastDestination(Icons.search_rounded, 'Search'),
  PodcastDestination(Icons.video_library_rounded, 'Library'),
];

class PodcastNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PodcastNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final n = kPodcastDestinations.length;
    final pillAlign = n == 1 ? 0.0 : (2 * currentIndex / (n - 1)) - 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: GlassContainer(
        radius: AppRadius.pill,
        blur: 24,
        shadow: kGlassShadow,
        fill: AppColors.glassFill,
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, c) {
            final slotWidth = c.maxWidth / n;
            return SizedBox(
              height: 48,
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: AppMotion.standard,
                    curve: AppMotion.spring,
                    alignment: Alignment(pillAlign, 0),
                    child: Container(
                      width: slotWidth - 6,
                      height: 48,
                      decoration: BoxDecoration(
                        // Podcast Mode holds a constant accent rather than
                        // tracking per-track artwork colour: episode art is a
                        // video frame, so a derived accent would flicker
                        // between unrelated hues every episode.
                        color: AppColors.accent.withOpacity(0.24),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(n, (i) {
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            AppHaptics.selection();
                            onTap(i);
                          },
                          child: _NavItem(
                            dest: kPodcastDestinations[i],
                            selected: i == currentIndex,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final PodcastDestination dest;
  final bool selected;
  const _NavItem({required this.dest, required this.selected});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.06 : 0.92,
            duration: AppMotion.standard,
            curve: AppMotion.spring,
            child: Icon(dest.icon,
                size: 21,
                color: selected ? Colors.white : AppColors.textTertiary),
          ),
          AnimatedSize(
            duration: AppMotion.fast,
            curve: AppMotion.standardCurve,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: AppMotion.fast,
              curve: AppMotion.standardCurve,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(dest.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: AppText.navLabel()),
                    )
                  : const SizedBox(width: 0, height: 0),
            ),
          ),
        ],
      );
}

/// Desktop rail for Podcast Mode, mirroring DesktopSidebar's language without
/// touching it (that widget is bound to the music nav set).
class PodcastSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool collapsed;

  /// Placed under the nav items — the mode switch back to Music.
  final Widget? footer;

  const PodcastSidebar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.collapsed = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 72 : 220,
      color: AppColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : 20, vertical: 24),
            child: collapsed
                ? const Center(
                    child: Icon(Icons.podcasts_rounded,
                        color: AppColors.accent, size: 24))
                : const Text('Podcasts',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
          for (var i = 0; i < kPodcastDestinations.length; i++)
            _SidebarItem(
              dest: kPodcastDestinations[i],
              selected: i == currentIndex,
              collapsed: collapsed,
              onTap: () => onTap(i),
            ),
          const Spacer(),
          if (footer != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 16, 0, collapsed ? 8 : 16, 20),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final PodcastDestination dest;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.dest,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final collapsed = widget.collapsed;
    final bg = active
        ? AppColors.accent.withOpacity(0.22)
        : (_hover ? Colors.white.withOpacity(0.06) : Colors.transparent);
    final iconColor = active ? Colors.white : AppColors.textTertiary;

    final body = collapsed
        ? Center(child: Icon(widget.dest.icon, size: 22, color: iconColor))
        : Row(children: [
            Icon(widget.dest.icon, size: 22, color: iconColor),
            const SizedBox(width: 14),
            Flexible(
              child: Text(widget.dest.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color:
                          active ? Colors.white : AppColors.textSecondary)),
            ),
          ]);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin:
              EdgeInsets.symmetric(horizontal: collapsed ? 10 : 12, vertical: 3),
          padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 14, vertical: 12),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: collapsed
              ? Tooltip(message: widget.dest.label, child: body)
              : body,
        ),
      ),
    );
  }
}
