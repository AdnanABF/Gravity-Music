// podcast/ui/podcast_library_screen.dart
//
// The podcast library (spec §11): Following, Saved, Downloaded, Recently
// Played, Completed.
//
// Wholly separate from the music library: following a show is not liking a
// song, and none of these sections read LibraryBox. The music LibraryScreen —
// liked songs, playlists, imports, downloads, the cloud account row — is
// untouched and still the only thing Music Mode shows.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ui/app_theme.dart';
import '../../ui/shell/responsive.dart';
import '../../ui/theme/glass.dart';
import '../../ui/theme/motion.dart';
import '../../ui/widgets/common_widgets.dart';
import '../controllers/podcast_library_controller.dart';
import '../controllers/podcast_player_controller.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import '../services/podcast_history_service.dart';
import 'podcast_episode_screen.dart';
import 'podcast_shell.dart';
import 'podcast_show_screen.dart';
import 'widgets/episode_actions.dart';
import 'widgets/episode_tile.dart';
import 'widgets/show_card.dart';

enum _Tab { following, saved, downloaded, recent, completed }

/// Following is the FIRST section here, not a separate tab — one place for
/// everything the listener has kept.
class PodcastLibraryScreen extends StatefulWidget {
  const PodcastLibraryScreen({super.key});

  @override
  State<PodcastLibraryScreen> createState() => _PodcastLibraryScreenState();
}

class _PodcastLibraryScreenState extends State<PodcastLibraryScreen> {
  late _Tab _tab = _Tab.following;

  static const _labels = {
    _Tab.following: 'Following',
    _Tab.saved: 'Saved',
    _Tab.downloaded: 'Downloaded',
    _Tab.recent: 'Recently Played',
    _Tab.completed: 'Completed',
  };

  @override
  Widget build(BuildContext context) {
    final library = Get.find<PodcastLibraryController>();
    final player = Get.find<PodcastPlayerController>();

    const tabs = _Tab.values;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMargin, 16, AppSpacing.screenMargin, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Library',
                      style: AppText.heading(size: 32)),
                ),
                GlassIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: library.reload,
                ),
              ],
            ),
          ),
          SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenMargin),
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = tabs[i];
                  final selected = t == _tab;
                  return Pressable(
                    onTap: () => setState(() => _tab = t),
                    pressedScale: 0.95,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent
                            : AppColors.glassFill,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                            color: AppColors.glassBorder, width: 1),
                      ),
                      child: Obx(() => Text(_chipLabel(library, t),
                          style: AppText.button().copyWith(
                              letterSpacing: 0,
                              color: selected
                                  ? Colors.white
                                  : AppColors.textSecondaryHi))),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            // Every branch below MUST read its RxList inside this closure —
            // hence `.toList()` rather than passing the RxList straight
            // through. Handing an RxList to a child widget as a plain List
            // reads nothing here, so Obx sees no observable, throws ObxError,
            // and release builds paint a blank grey ErrorWidget where the list
            // should be. `.toList()` iterates, which registers the read.
            child: Obx(() {
              switch (_tab) {
                case _Tab.following:
                  return _ShowList(
                    shows: library.following.toList(),
                    emptyIcon: Icons.podcasts_rounded,
                    emptyTitle: 'Not following anything yet',
                    emptyMessage:
                        'Follow a show and its new episodes will appear on Home.',
                    onOpen: (s) => _openShow(context, s),
                    trailingFor: (s) => FollowButton(
                      following: true,
                      compact: true,
                      onTap: () => library.toggleFollow(s),
                    ),
                  );

                case _Tab.saved:
                  return _EpisodeList(
                    episodes: library.saved.toList(),
                    player: player,
                    emptyIcon: Icons.bookmark_border_rounded,
                    emptyTitle: 'No saved episodes',
                    emptyMessage:
                        'Save an episode to keep it here for later.',
                  );

                case _Tab.downloaded:
                  return _EpisodeList(
                    episodes: library.downloaded.toList(),
                    player: player,
                    emptyIcon: Icons.download_rounded,
                    emptyTitle: 'No downloads',
                    emptyMessage:
                        'Downloaded episodes play with no network at all.',
                  );

                case _Tab.recent:
                  return _EpisodeList(
                    episodes:
                        library.recent.map((e) => e.episode).toList(),
                    player: player,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'Nothing played yet',
                    emptyMessage:
                        'Episodes you start show up here with your place kept.',
                  );

                case _Tab.completed:
                  return _EpisodeList(
                    episodes:
                        library.completed.map((e) => e.episode).toList(),
                    player: player,
                    emptyIcon: Icons.check_circle_outline_rounded,
                    emptyTitle: 'No finished episodes',
                    emptyMessage:
                        'Episodes you finish are collected here.',
                  );
              }
            }),
          ),
        ],
      ),
    );
  }

  /// "Following · 3" — a count on each chip, so what's inside a section is
  /// visible without opening it. Reads each RxList, which is also what keeps
  /// this Obx valid (see the note on the section switch below).
  String _chipLabel(PodcastLibraryController library, _Tab t) {
    final count = switch (t) {
      _Tab.following => library.following.length,
      _Tab.saved => library.saved.length,
      _Tab.downloaded => library.downloaded.length,
      _Tab.recent => library.recent.length,
      _Tab.completed => library.completed.length,
    };
    return count == 0 ? _labels[t]! : '${_labels[t]!} · $count';
  }

  void _openShow(BuildContext context, PodcastShow s) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PodcastShowScreen(
              showId: s.id, title: s.title, artwork: s.artwork)));
}

class _ShowList extends StatelessWidget {
  final List<PodcastShow> shows;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final void Function(PodcastShow) onOpen;
  final Widget Function(PodcastShow)? trailingFor;

  const _ShowList({
    required this.shows,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onOpen,
    this.trailingFor,
  });

  @override
  Widget build(BuildContext context) {
    if (shows.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        action: GlassPillButton(
          icon: Icons.explore_rounded,
          label: 'Browse Discover',
          onTap: () =>
              PodcastShellNav.goToTab?.call(PodcastShellNav.discoverTabIndex),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomDockInset(context) + 24),
      itemCount: shows.length,
      itemBuilder: (_, i) => ShowTile(
        show: shows[i],
        onTap: () => onOpen(shows[i]),
        trailing: trailingFor?.call(shows[i]),
      ),
    );
  }
}

class _EpisodeList extends StatelessWidget {
  final List<PodcastEpisode> episodes;
  final PodcastPlayerController player;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  const _EpisodeList({
    required this.episodes,
    required this.player,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return EmptyState(
          icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: bottomDockInset(context) + 24),
      itemCount: episodes.length,
      separatorBuilder: (_, __) => const Divider(
          height: 1,
          indent: AppSpacing.screenMargin,
          endIndent: AppSpacing.screenMargin,
          color: AppColors.borderSoft),
      itemBuilder: (_, i) {
        // Prefer the richer snapshot history kept, if there is one — a
        // download row stores what was on screen when it was queued.
        final stored = PodcastHistoryService.episodeFor(episodes[i].id);
        final e = stored ?? episodes[i];
        return EpisodeTile(
          episode: e,
          showDescription: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PodcastEpisodeScreen(episode: e))),
          onPlay: () =>
              player.isCurrent(e.id) ? player.togglePlayPause() : player.play(e),
          onMore: () => showEpisodeActions(context, e),
        );
      },
    );
  }
}
