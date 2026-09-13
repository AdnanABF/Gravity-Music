// podcast/services/podcast_prefs.dart
//
// Podcast-only preferences, kept in the podcast box rather than 'AppPrefs'.
//
// The selected MODE lives here too. That is deliberate: the app's music
// persistence (session, quality, volume, search history) is in 'AppPrefs', and
// adding a podcast key there would put podcast state on the same restore path
// as music state. A separate box means podcast preferences cannot corrupt,
// collide with, or slow down anything music restores at startup.

import 'package:hive/hive.dart';

import '../models/podcast_episode.dart';

/// The two halves of the app.
enum AppMode { music, podcast }

class PodcastPrefs {
  static Box get _box => Hive.box('PodcastBox');

  static const _key = 'prefs';

  static Map<String, dynamic> _read() {
    final raw = _box.get(_key);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static void _write(String field, Object? value) {
    final m = _read()..[field] = value;
    _box.put(_key, m);
  }

  // ── Mode ──────────────────────────────────────────────────────────────────

  /// The mode the app was last in. Music is the default, so an existing
  /// install that has never opened Podcast Mode starts exactly as before.
  static AppMode get mode =>
      _read()['mode'] == 'podcast' ? AppMode.podcast : AppMode.music;

  static set mode(AppMode m) =>
      _write('mode', m == AppMode.podcast ? 'podcast' : 'music');

  /// Whether the Music ⇄ Podcasts switch is shown on the main screen, set from
  /// Settings. OFF by default: with it off, the main screen is exactly what it
  /// was before Podcast Mode existed, and Podcasts is something a user opts
  /// into rather than a new control on everyone's home screen.
  static bool get switchEnabled => _read()['switchEnabled'] == true;

  static set switchEnabled(bool v) => _write('switchEnabled', v);

  // ── Playback speed ────────────────────────────────────────────────────────

  /// Speeds offered in the player.
  static const List<double> speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// Remembered podcast speed. Independent of music: music never reads this,
  /// and the podcast player resets the shared engine to 1.0× whenever a
  /// non-podcast item becomes current, so a 1.5× podcast can't leave music
  /// playing fast.
  static double get speed {
    final v = (_read()['speed'] as num?)?.toDouble() ?? 1.0;
    return speeds.contains(v) ? v : 1.0;
  }

  static set speed(double v) => _write('speed', v);

  // ── Skip intervals ────────────────────────────────────────────────────────

  /// Podcast convention: a short jump back (missed a sentence) and a longer
  /// jump forward (skipping an ad break).
  static int get skipBackSeconds =>
      (_read()['skipBack'] as num?)?.toInt() ?? 15;

  static set skipBackSeconds(int s) => _write('skipBack', s);

  static int get skipForwardSeconds =>
      (_read()['skipForward'] as num?)?.toInt() ?? 30;

  static set skipForwardSeconds(int s) => _write('skipForward', s);

  static const List<int> skipOptions = [10, 15, 30, 45, 60];

  // ── Last podcast session ──────────────────────────────────────────────────

  /// The episode loaded when the app was last closed, restored (paused, at
  /// its saved position) on the next cold start. Its position is NOT stored
  /// here — that lives in the history store, so there is one source of truth
  /// for "where am I in this episode".
  static PodcastEpisode? get lastEpisode {
    final raw = _box.get('lastEpisode');
    if (raw is! Map) return null;
    final e = PodcastEpisode.fromMap(raw);
    return e.id.isEmpty ? null : e;
  }

  static set lastEpisode(PodcastEpisode? e) => e == null
      ? _box.delete('lastEpisode')
      : _box.put('lastEpisode', e.toMap());
}
