// ui/shell/root_shell.dart
//
// The app's root scaffold. All tabs stay mounted in an IndexedStack
// (scroll/state preserved), but ONLY the active screen is painted — the prior
// Stack+AnimatedOpacity approach kept every screen painting and, during a
// switch, composited two full blurred screens at once (the #1 measured jank
// source). The soft transition feel is preserved with a short fade-through
// applied to the *incoming* screen only (the same language as the app's page
// pushes), so two blurred screens are never composited simultaneously.
// The floating mini-player + nav dock are layered above the content
// (DESIGN.md → "Glass Layer floating above the content stack"). Screens add
// AppSpacing.bottomDock padding so nothing hides behind the dock.
//
// This file is also the app's MODE SWITCH point: it renders either the music
// shell built here or Podcast Mode's own PodcastShell, keeping both mounted
// so neither loses state when the user flips between them. That is the whole
// extent of the coupling — every podcast screen, service and model lives
// under lib/podcast/ and is never referenced by music code.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../podcast/controllers/podcast_mode_controller.dart';
import '../../podcast/ui/podcast_shell.dart';
import '../../podcast/ui/widgets/mode_switch.dart';
import '../../podcast/ui/widgets/podcast_mini_player.dart';
import '../app_theme.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../queue/queue_screen.dart';
import '../search/search_screen.dart';
import '../theme/motion.dart';
import 'desktop_shell.dart';
import 'floating_nav_bar.dart';
import 'responsive.dart';

/// Lets non-descendant code (the global keyboard shortcuts, which are mounted
/// ABOVE the Navigator and so can't reach RootShell's State) switch tabs.
/// Set while a RootShell is mounted, cleared on dispose.
class ShellNav {
  ShellNav._();

  static const int searchTabIndex = 1;

  static void Function(int index)? goToTab;
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // Built once and kept alive by the IndexedStack (state/scroll preserved).
  // Each is wrapped in a RepaintBoundary so a repaint in one tab can never
  // dirty another, and so the active screen rasterizes into its own layer.
  final _screens = const [
    RepaintBoundary(child: HomeScreen()),
    RepaintBoundary(child: SearchScreen()),
    RepaintBoundary(child: LibraryScreen()),
    RepaintBoundary(child: QueueScreen()),
  ];

  // Drives the incoming-screen fade. Rests at 1.0 (Opacity short-circuits the
  // saveLayer at exactly 1.0, so settled tabs cost nothing) and replays 0→1 on
  // each switch. A short fade only — tabs are peer-level, so no scale (peers
  // shouldn't "zoom"); 160ms lands at Spotify-level responsiveness while
  // keeping a whisper of Gravity's softness.
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
    ShellNav.goToTab = _onTap;
  }

  void _onTap(int i) {
    // Tapping "Queue" while something plays could also open Now Playing;
    // we keep it as a full tab here for discoverability.
    if (i == _index) return;
    setState(() => _index = i);
    _transition.forward(from: 0.0);
  }

  @override
  void dispose() {
    if (ShellNav.goToTab == _onTap) ShellNav.goToTab = null;
    _transition.dispose();
    super.dispose();
  }

  Widget _content() => FadeTransition(
        opacity: _fade,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: _screens,
        ),
      );

  /// The MUSIC shell — byte-for-byte the shell this file has always built,
  /// with two shell-level (not screen-level) additions for the mode switch:
  /// the dock's mini-player is chosen by what's playing, and a small
  /// "Podcasts" pill sits above it. No music SCREEN is touched.
  Widget _musicShell(BuildContext context) {
    // Shell is chosen by PLATFORM, not window width: desktop (Linux/Windows/
    // macOS) always gets the sidebar shell — even when the window is small —
    // instead of falling back to the Android floating-dock layout. Mobile is
    // untouched.
    if (isDesktopPlatform) {
      return Stack(
        children: [
          Positioned.fill(
            child: DesktopShell(
              content: _content(),
              currentIndex: _index,
              onTap: _onTap,
            ),
          ),
          // While a podcast episode is playing, its own bar covers the music
          // now-playing bar — otherwise an episode would render through music
          // chrome, with prev/next buttons that do nothing for it. Draws
          // nothing when no episode is loaded, so music is untouched.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PodcastDesktopDock(),
          ),
          // Sits in the empty space under the sidebar's nav items, above the
          // now-playing bar — placing it here means DesktopShell and
          // DesktopSidebar (both music widgets) need no changes.
          const Positioned(
            left: 14,
            bottom: 96,
            child: ModeSwitchPill(),
          ),
        ],
      );
    }
    // ── Mobile shell ──
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
                      // Collapses to nothing when the switch is off in Settings.
                      const ModeSwitchDockSlot(),
                      // Renders the untouched music MiniPlayer for songs, and
                      // the podcast bar if an episode is what's actually
                      // playing — so an episode is never drawn through music
                      // chrome, even while Music Mode is on screen.
                      const ModeAwareMiniPlayer(),
                      const SizedBox(height: 10),
                      FloatingNavBar(currentIndex: _index, onTap: _onTap),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  }

  /// Whether Podcast Mode's tree has been built yet this session.
  ///
  /// It is built LAZILY — on the first switch into podcast mode — because an
  /// IndexedStack builds all of its children, and PodcastHomeController loads
  /// its feed in onInit. Mounting it eagerly would fire a podcast network
  /// request on every cold start for users who never open Podcasts, which is
  /// a cost Music Mode never used to pay. Once built it STAYS mounted, so
  /// flipping between modes preserves both sides' scroll and state.
  bool _podcastMounted = false;

  @override
  Widget build(BuildContext context) {
    final mode = Get.find<PodcastModeController>();

    return Obx(() {
      final podcast = mode.isPodcast;
      if (podcast) _podcastMounted = true;

      // IndexedStack paints only the active branch, so the inactive mode
      // costs nothing per frame — the same reason this file uses one for tabs.
      return IndexedStack(
        index: podcast ? 1 : 0,
        sizing: StackFit.expand,
        children: [
          _musicShell(context),
          _podcastMounted
              ? const PodcastShell()
              : const SizedBox.shrink(),
        ],
      );
    });
  }
}
