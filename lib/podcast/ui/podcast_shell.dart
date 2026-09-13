// podcast/ui/podcast_shell.dart
//
// Podcast Mode's root scaffold — the podcast counterpart of RootShell, and the
// only thing RootShell has to know about.
//
// Structurally it mirrors the music shell (all tabs in an IndexedStack so
// scroll positions survive, the floating mini-player and nav dock layered
// above, a desktop sidebar variant), but it is its own widget with its own
// tab set, so nothing about Music Mode's shell had to change to make room.
//
// Switching modes does NOT dispose this tree: RootShell keeps both shells
// mounted, so returning to Podcasts finds Home exactly where it was left.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/shell/now_playing_bar.dart';
import '../../ui/shell/responsive.dart';
import '../../ui/theme/motion.dart';
import '../controllers/podcast_player_controller.dart';
import 'podcast_discover_screen.dart';
import 'podcast_home_screen.dart';
import 'podcast_library_screen.dart';
import 'podcast_nav_bar.dart';
import 'podcast_search_screen.dart';
import 'widgets/mode_switch.dart';
import 'widgets/podcast_mini_player.dart';

/// Lets podcast screens switch tabs from outside the shell's State (empty
/// states link to Search / Discover). Mirrors music's ShellNav.
class PodcastShellNav {
  PodcastShellNav._();

  static const int homeTabIndex = 0;
  static const int discoverTabIndex = 1;
  static const int searchTabIndex = 2;
  static const int libraryTabIndex = 3;

  static void Function(int index)? goToTab;
}

class PodcastShell extends StatefulWidget {
  const PodcastShell({super.key});

  @override
  State<PodcastShell> createState() => _PodcastShellState();
}

class _PodcastShellState extends State<PodcastShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // Each tab is wrapped in a RepaintBoundary so a repaint in one can't dirty
  // another — the same discipline the music shell uses for its blur-heavy
  // surfaces.
  final _screens = const [
    RepaintBoundary(child: PodcastHomeScreen()),
    RepaintBoundary(child: PodcastDiscoverScreen()),
    RepaintBoundary(child: PodcastSearchScreen()),
    RepaintBoundary(child: PodcastLibraryScreen()),
  ];

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: AppMotion.micro,
    value: 1.0,
  );
  late final Animation<double> _fade =
      _transition.drive(CurveTween(curve: AppMotion.standardCurve));

  @override
  void initState() {
    super.initState();
    PodcastShellNav.goToTab = _onTap;
  }

  @override
  void dispose() {
    if (PodcastShellNav.goToTab == _onTap) PodcastShellNav.goToTab = null;
    _transition.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _transition.forward(from: 0.0);
  }

  Widget _content() => FadeTransition(
        opacity: _fade,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: _screens,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final collapsed = c.maxWidth < kSidebarCollapseWidth;
                return Row(
                  children: [
                    PodcastSidebar(
                      currentIndex: _index,
                      onTap: _onTap,
                      collapsed: collapsed,
                      footer: ModeSwitchPill(compact: collapsed),
                    ),
                    Expanded(child: _content()),
                  ],
                );
              }),
            ),
            // On desktop the podcast bar docks above the music now-playing bar
            // only when an episode is loaded; otherwise the music bar handles
            // whatever is playing, exactly as it does in Music Mode.
            const _DesktopPlayerDock(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Same slot as the music shell — the switch must not move
                    // when the mode does, or it stops reading as one control.
                    const ModeSwitchDockSlot(),
                    const ModeAwareMiniPlayer(),
                    const SizedBox(height: 10),
                    PodcastNavBar(currentIndex: _index, onTap: _onTap),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop bottom dock: the podcast bar when an episode is loaded, the
/// existing music now-playing bar otherwise. Music Mode layers the very same
/// PodcastDesktopDock over its bar, so the two modes are indistinguishable
/// while an episode plays.
class _DesktopPlayerDock extends StatelessWidget {
  const _DesktopPlayerDock();

  @override
  Widget build(BuildContext context) {
    final player = podcastPlayerOrNull;
    if (player == null) return const NowPlayingBar();
    return Obx(() => player.currentEpisode.value == null
        ? const NowPlayingBar()
        : const PodcastDesktopDock());
  }
}
