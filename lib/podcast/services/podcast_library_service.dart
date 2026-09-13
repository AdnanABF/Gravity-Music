// podcast/services/podcast_library_service.dart
//
// The podcast library: shows you FOLLOW and episodes you SAVE. Stored in Hive
// box 'PodcastBox', with no relationship to LibraryBox — following a podcast
// is not liking a song, and a saved episode is not a playlist entry. Music's
// liked songs and playlists are untouched and unaware of any of this.
//
// Schema (PodcastBox):
//   'following' → List<Map>  PodcastShow.toMap(), most recently followed first
//   'saved'     → List<Map>  PodcastEpisode.toMap(), most recently saved first
//   'prefs'     → Map        podcast-only preferences (see PodcastPrefs)

import 'package:hive/hive.dart';

import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';

class PodcastLibraryService {
  static Box get _box => Hive.box('PodcastBox');

  static const _followingKey = 'following';
  static const _savedKey = 'saved';

  /// Fires after any mutation so controllers can refresh without polling.
  static final List<void Function()> _listeners = [];

  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);

  static void _notify() {
    for (final fn in List<void Function()>.from(_listeners)) {
      fn();
    }
  }

  static List<Map> _raw(String key) =>
      (_box.get(key, defaultValue: <Map>[]) as List).cast<Map>();

  // ── Following ─────────────────────────────────────────────────────────────

  static List<PodcastShow> following() => _raw(_followingKey)
      .map((m) => PodcastShow.fromMap(Map.from(m)))
      .where((s) => s.id.isNotEmpty)
      .toList();

  static bool isFollowing(String showId) =>
      _raw(_followingKey).any((m) => m['id'] == showId);

  /// Follows [show], or refreshes its stored metadata if already followed.
  static void follow(PodcastShow show) {
    if (show.id.isEmpty) return;
    final list = _raw(_followingKey).where((m) => m['id'] != show.id).toList();
    list.insert(0, show.toMap());
    _box.put(_followingKey, list);
    _notify();
  }

  /// Refreshes a FOLLOWED show's stored metadata from a freshly fetched page,
  /// in place (order preserved), without re-following it.
  ///
  /// This is what repairs follows whose art has gone blank. A show cover is a
  /// signed URL that expires, so the one captured at follow time eventually
  /// 404s; every time the show's page is fetched anywhere in the app, the
  /// stored entry picks up the current URL and the creator's avatar. Empty
  /// fields never overwrite filled ones, and nothing is written or announced
  /// unless something actually changed.
  static void refreshMetadata(PodcastShow fresh) {
    if (fresh.id.isEmpty) return;
    final list = _raw(_followingKey);
    final i = list.indexWhere((m) => m['id'] == fresh.id);
    if (i < 0) return;

    final old = PodcastShow.fromMap(Map.from(list[i]));
    String pick(String next, String prev) => next.isNotEmpty ? next : prev;
    final merged = old.copyWith(
      title: pick(fresh.title, old.title),
      author: pick(fresh.author, old.author),
      artwork: pick(fresh.artwork, old.artwork),
      description: pick(fresh.description, old.description),
      channelId: pick(fresh.channelId, old.channelId),
      avatar: pick(fresh.avatar, old.avatar),
    );

    final updated = Map<String, dynamic>.from(merged.toMap())
      ..['refreshedMs'] = DateTime.now().millisecondsSinceEpoch;
    final changed = merged.title != old.title ||
        merged.author != old.author ||
        merged.artwork != old.artwork ||
        merged.description != old.description ||
        merged.avatar != old.avatar;

    final next = List<Map>.from(list)..[i] = updated;
    _box.put(_followingKey, next);
    if (changed) _notify();
  }

  /// Followed shows whose stored metadata is old enough — or old-format
  /// enough (no avatar) — to be worth re-fetching.
  static List<PodcastShow> followsNeedingRefresh(
      {Duration maxAge = const Duration(hours: 12)}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _raw(_followingKey)
        .where((m) {
          final at = (m['refreshedMs'] as num?)?.toInt() ?? 0;
          final noAvatar = (m['avatar'] ?? '').toString().isEmpty;
          return noAvatar || now - at > maxAge.inMilliseconds;
        })
        .map((m) => PodcastShow.fromMap(Map.from(m)))
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  static void unfollow(String showId) {
    _box.put(_followingKey,
        _raw(_followingKey).where((m) => m['id'] != showId).toList());
    _notify();
  }

  /// Returns the new state, so callers can render a toast without re-reading.
  static bool toggleFollow(PodcastShow show) {
    if (isFollowing(show.id)) {
      unfollow(show.id);
      return false;
    }
    follow(show);
    return true;
  }

  // ── Saved episodes ────────────────────────────────────────────────────────

  static List<PodcastEpisode> saved() => _raw(_savedKey)
      .map((m) => PodcastEpisode.fromMap(Map.from(m)))
      .where((e) => e.id.isNotEmpty)
      .toList();

  static bool isSaved(String episodeId) =>
      _raw(_savedKey).any((m) => m['id'] == episodeId);

  static void save(PodcastEpisode episode) {
    if (episode.id.isEmpty) return;
    final list = _raw(_savedKey).where((m) => m['id'] != episode.id).toList();
    list.insert(0, episode.toMap());
    _box.put(_savedKey, list);
    _notify();
  }

  static void unsave(String episodeId) {
    _box.put(
        _savedKey, _raw(_savedKey).where((m) => m['id'] != episodeId).toList());
    _notify();
  }

  static bool toggleSave(PodcastEpisode episode) {
    if (isSaved(episode.id)) {
      unsave(episode.id);
      return false;
    }
    save(episode);
    return true;
  }
}
