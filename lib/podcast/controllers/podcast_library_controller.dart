// podcast/controllers/podcast_library_controller.dart
//
// Reactive view of the podcast library: followed shows, saved episodes,
// downloads (with in-flight progress), recently played and completed.
//
// Downloads live here rather than in a fourth controller because in Podcast
// Mode a download IS a library section — there's no separate Downloads tab.

import 'package:get/get.dart';

import '../models/podcast_episode.dart';
import '../models/podcast_show.dart';
import '../services/podcast_download_service.dart';
import '../services/podcast_history_service.dart';
import '../services/podcast_library_service.dart';
import '../services/podcast_service.dart';

class PodcastLibraryController extends GetxController {
  final following = <PodcastShow>[].obs;
  final saved = <PodcastEpisode>[].obs;
  final downloaded = <PodcastEpisode>[].obs;
  final recent = <PodcastHistoryEntry>[].obs;
  final completed = <PodcastHistoryEntry>[].obs;

  /// episodeId → 0..1 while a download is running.
  final downloading = <String, double>{}.obs;

  /// episodeIds the user asked to cancel; the download loop polls this.
  final _cancelled = <String>{};

  late final void Function() _listener;

  @override
  void onInit() {
    super.onInit();
    _listener = reload;
    PodcastLibraryService.addListener(_listener);
    reload();
    // Repair followed shows whose stored cover URL may have expired (signed
    // URLs do) or that predate the creator avatar. Delayed off the cold-start
    // path; a no-op for anyone who follows nothing, so music-only users make
    // no request.
    Future.delayed(const Duration(seconds: 3), () {
      final stale = PodcastLibraryService.followsNeedingRefresh();
      if (stale.isNotEmpty) PodcastService.healFollowed(stale);
    });
  }

  @override
  void onClose() {
    PodcastLibraryService.removeListener(_listener);
    super.onClose();
  }

  /// Named `reload` rather than `refresh` because GetxController already
  /// declares a `refresh()` with different semantics (widget rebuild).
  void reload() {
    following.assignAll(PodcastLibraryService.following());
    saved.assignAll(PodcastLibraryService.saved());
    downloaded.assignAll(PodcastDownloadService.downloads());
    recent.assignAll(PodcastHistoryService.recent(limit: 40));
    completed.assignAll(PodcastHistoryService.completed(limit: 40));
  }

  // ── Follow / save ─────────────────────────────────────────────────────────

  bool isFollowing(String showId) => PodcastLibraryService.isFollowing(showId);

  bool toggleFollow(PodcastShow show) =>
      PodcastLibraryService.toggleFollow(show);

  bool isSaved(String episodeId) => PodcastLibraryService.isSaved(episodeId);

  bool toggleSave(PodcastEpisode episode) =>
      PodcastLibraryService.toggleSave(episode);

  // ── Downloads ─────────────────────────────────────────────────────────────

  bool isDownloaded(String episodeId) =>
      PodcastDownloadService.isDownloaded(episodeId);

  bool isDownloading(String episodeId) => downloading.containsKey(episodeId);

  /// Downloads [episode], streaming progress into [downloading]. Errors are
  /// surfaced by returning the message; the caller decides how to show it.
  Future<String?> download(PodcastEpisode episode) async {
    if (isDownloaded(episode.id) || isDownloading(episode.id)) return null;
    downloading[episode.id] = 0.0;
    _cancelled.remove(episode.id);
    try {
      await PodcastDownloadService.download(
        episode,
        onProgress: (p) => downloading[episode.id] = p,
        isCancelled: () => _cancelled.contains(episode.id),
      );
      downloaded.assignAll(PodcastDownloadService.downloads());
      return null;
    } on PodcastDownloadCancelled {
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      downloading.remove(episode.id);
      _cancelled.remove(episode.id);
    }
  }

  void cancelDownload(String episodeId) => _cancelled.add(episodeId);

  Future<void> removeDownload(String episodeId) async {
    await PodcastDownloadService.remove(episodeId);
    downloaded.assignAll(PodcastDownloadService.downloads());
  }
}
