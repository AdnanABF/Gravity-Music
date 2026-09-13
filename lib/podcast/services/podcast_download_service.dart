// podcast/services/podcast_download_service.dart
//
// Offline episodes. Mirrors the SHAPE of the music DownloadService (resolve a
// stream in an isolate, stream bytes to a .part file, rename on success) but
// keeps its own metadata in 'PodcastBox' and its own folder on disk, so:
//
//   • a downloaded episode never appears in the music Downloads tab, and
//   • clearing music downloads never deletes episodes (or vice versa).
//
// The only music code involved is `getStreamInfo` — the isolate entry point
// that turns a videoId into an audio URL. That is genuinely shared low-level
// infrastructure (spec §15), not domain logic, and it is called, not modified.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../../models/hm_streaming_data.dart';
import '../../services/app_paths.dart';
import '../../services/background_task.dart';
import '../models/podcast_episode.dart';

/// Thrown when the user cancels an in-flight download.
class PodcastDownloadCancelled implements Exception {
  const PodcastDownloadCancelled();
}

class PodcastDownloadService {
  static Box get _box => Hive.box('PodcastBox');
  static const _key = 'downloads';

  static List<Map> _raw() =>
      (_box.get(_key, defaultValue: <Map>[]) as List).cast<Map>();

  static List<PodcastEpisode> downloads() => _raw()
      .map((m) => PodcastEpisode.fromMap(Map.from(m)))
      .where((e) => e.id.isNotEmpty)
      .toList();

  static bool isDownloaded(String episodeId) =>
      _raw().any((m) => m['id'] == episodeId);

  static Map? _metaFor(String episodeId) {
    for (final m in _raw()) {
      if (m['id'] == episodeId) return m;
    }
    return null;
  }

  /// `file://` URL for offline playback, or null when not downloaded / the
  /// file has been removed underneath us. Consulted by the audio handler's
  /// checkNGetUrl alongside the two music download stores.
  static String? playbackUrlFor(String episodeId) {
    final path = _metaFor(episodeId)?['path'] as String?;
    if (path == null || !File(path).existsSync()) return null;
    return 'file://$path';
  }

  static double loudnessFor(String episodeId) =>
      (_metaFor(episodeId)?['loudnessDb'] as num?)?.toDouble() ?? 0.0;

  static Future<String> _dir() async {
    final base = await appDataDirectory();
    final dir = Directory('${base.path}/podcast_downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<void> remove(String episodeId) async {
    final path = _metaFor(episodeId)?['path'] as String?;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    _box.put(_key, _raw().where((m) => m['id'] != episodeId).toList());
  }

  /// Downloads [episode] to the podcast folder, reporting 0..1 progress.
  static Future<void> download(
    PodcastEpisode episode, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final token = RootIsolateToken.instance!;
    final json = await Isolate.run(() => getStreamInfo(episode.id, token));
    final data = HMStreamingData.fromJson(json);
    if (!data.playable || data.audio == null) {
      throw Exception(
          data.statusMSG.isEmpty ? 'Episode unavailable' : data.statusMSG);
    }
    final audio = data.audio!;

    final dir = await _dir();
    final file = File('$dir/${episode.id}.m4a');
    final part = File('$dir/${episode.id}.m4a.part');

    final client = http.Client();
    IOSink? sink;
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(audio.url)));
      final total = resp.contentLength ?? audio.size;
      sink = part.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        if (isCancelled?.call() ?? false) throw const PodcastDownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }

    final list = _raw().where((m) => m['id'] != episode.id).toList();
    list.insert(0, {
      ...episode.toMap(),
      'path': file.path,
      'loudnessDb': audio.loudnessDb,
    });
    _box.put(_key, list);
    onProgress?.call(1.0);
  }
}
