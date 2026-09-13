// podcast/controllers/podcast_home_controller.dart
//
// Backing state for Podcast Home. One call to the recommender fills every
// section, so the screen isn't N independent loading spinners.

import 'dart:async';

import 'package:get/get.dart';

import '../models/podcast_episode.dart';
import '../services/podcast_history_service.dart';
import '../services/podcast_library_service.dart';
import '../services/podcast_recommendation_service.dart';
import '../services/yt_podcast_api.dart';

class PodcastHomeController extends GetxController {
  final continueListening = <PodcastHistoryEntry>[].obs;
  final newEpisodes = <PodcastEpisode>[].obs;
  final picked = <PodcastEpisode>[].obs;
  final recommended = <ShowRecommendation>[].obs;
  final shelves = <PodcastShelf>[].obs;

  final loading = false.obs;
  final loaded = false.obs;

  late final void Function() _libraryListener;
  Timer? _reloadDebounce;

  @override
  void onInit() {
    super.onInit();
    // Following a show from anywhere should change Home's "Your Shows" and
    // "New episodes" without a manual refresh.
    _libraryListener = () {
      continueListening.assignAll(PodcastHistoryService.continueListening());
      // Debounced: a follow, a save, and a metadata repair can all notify
      // within a second, and each used to rebuild every section.
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 800), () {
        if (loaded.value) load();
      });
    };
    PodcastLibraryService.addListener(_libraryListener);
    load();
  }

  @override
  void onClose() {
    _reloadDebounce?.cancel();
    PodcastLibraryService.removeListener(_libraryListener);
    super.onClose();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (loading.value) return;
    loading.value = true;
    // Continue Listening is local — show it immediately, before the network.
    continueListening.assignAll(PodcastHistoryService.continueListening());
    try {
      final recs =
          await PodcastRecommendationService.build(forceRefresh: forceRefresh);
      continueListening.assignAll(recs.continueListening);
      newEpisodes.assignAll(recs.newFromYourShows);
      picked.assignAll(recs.pickedForYou);
      recommended.assignAll(recs.recommendedShows);
      shelves.assignAll(recs.shelves);
      loaded.value = true;
    } finally {
      loading.value = false;
    }
  }

  /// Cheap local refresh after playback changes something (progress, a
  /// completion) — no network.
  void refreshProgress() =>
      continueListening.assignAll(PodcastHistoryService.continueListening());

  bool get isEmpty =>
      continueListening.isEmpty &&
      newEpisodes.isEmpty &&
      picked.isEmpty &&
      recommended.isEmpty &&
      shelves.isEmpty;
}
