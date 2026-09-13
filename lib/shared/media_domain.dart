// shared/media_domain.dart
//
// The ONE piece of vocabulary Music Mode and Podcast Mode share: a marker on
// a MediaItem saying which domain it came from.
//
// Both modes play through the same audio_service handler (there can only be
// one per app — it owns the notification, the lockscreen/MPRIS contract and,
// on Android, the foreground service that keeps background playback alive).
// That means a few pieces of *music* machinery observe the shared queue and
// would otherwise act on podcast episodes: the autoplay orchestrator would
// refill a podcast queue with music radio, and the listening-history store
// would fold episodes into the taste profile behind "Made For You".
//
// Rather than have music code import podcast code (or vice versa) to ask
// "is this mine?", both sides import this neutral file. Music code uses it
// only to *opt out* of podcast items — its behaviour for real music items is
// bit-for-bit what it was before, because a music MediaItem never carries the
// flag.

import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// Key written into `MediaItem.extras` by podcast code. Music never sets it.
const String kMediaDomainKey = 'gravity_domain';

/// Value for podcast episodes.
const String kDomainPodcast = 'podcast';

/// True when [item] is a podcast episode rather than a music track.
///
/// Deliberately tolerant: `extras` is null on some restored/legacy items, and
/// a missing flag always means "music", which is the safe default (music code
/// keeps its existing behaviour).
bool isPodcastItem(MediaItem? item) =>
    item?.extras?[kMediaDomainKey] == kDomainPodcast;

/// Which domain owned the engine most recently, persisted so a cold start can
/// bring back THAT session rather than always the music one.
///
/// Without this, closing the app mid-episode and reopening it restored the
/// last MUSIC queue: music's session restore runs unconditionally at startup,
/// and (correctly) never saves podcast episodes into its own session. Now the
/// two restores defer to each other through this single flag.
///
/// Written only by the podcast player, which already observes every item the
/// shared engine plays. Music code only reads it. Stored in 'AppPrefs'
/// because it describes the shared engine, not either domain's data; a
/// missing value means "music", so existing installs start exactly as before.
class LastPlaybackDomain {
  LastPlaybackDomain._();

  static const _key = 'lastPlaybackDomain';

  static bool get isPodcast {
    try {
      return Hive.box('AppPrefs').get(_key) == kDomainPodcast;
    } catch (_) {
      return false; // box not open (tests) → the safe, pre-existing default
    }
  }

  static void set({required bool podcast}) {
    try {
      final box = Hive.box('AppPrefs');
      final value = podcast ? kDomainPodcast : 'music';
      if (box.get(_key) != value) box.put(_key, value);
    } catch (_) {}
  }
}
