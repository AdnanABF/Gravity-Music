// podcast/controllers/podcast_mode_controller.dart
//
// Which half of the app is on screen. Registered at startup so the shell can
// read it on the first frame; the selection is persisted in the podcast box
// (never in 'AppPrefs' — see PodcastPrefs for why).
//
// Switching modes changes only what is DRAWN. It does not stop playback, move
// a queue, or migrate any state: Music Mode's screens stay mounted and keep
// their scroll positions, and Podcast Mode's do the same.

import 'package:get/get.dart';

import '../services/podcast_prefs.dart';

class PodcastModeController extends GetxController {
  final mode = AppMode.music.obs;

  /// Settings → "Show Music / Podcasts switch". Drives whether the switch is
  /// rendered at all.
  final switchEnabled = false.obs;

  bool get isPodcast => mode.value == AppMode.podcast;

  @override
  void onInit() {
    super.onInit();
    switchEnabled.value = PodcastPrefs.switchEnabled;
    // With the switch hidden there is no way back to Music from Podcast Mode,
    // so a persisted podcast mode is never restored behind a disabled switch.
    mode.value = switchEnabled.value ? PodcastPrefs.mode : AppMode.music;
  }

  /// Shows or hides the switch. Hiding it also returns to Music Mode — the
  /// switch is the only way out of Podcast Mode, so leaving the user there
  /// with it gone would strand them.
  void setSwitchEnabled(bool enabled) {
    switchEnabled.value = enabled;
    PodcastPrefs.switchEnabled = enabled;
    if (!enabled) switchTo(AppMode.music);
  }

  void switchTo(AppMode next) {
    if (mode.value == next) return;
    mode.value = next;
    PodcastPrefs.mode = next;
  }

  void toggle() =>
      switchTo(isPodcast ? AppMode.music : AppMode.podcast);
}
