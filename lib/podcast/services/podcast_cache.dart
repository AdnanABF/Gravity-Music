// podcast/services/podcast_cache.dart
//
// TTL'd JSON cache for podcast network responses, in its own Hive box
// ('PodcastCache'). Same idea as the music CacheService, but a separate box
// so a podcast cache clear can never drop the music home/mix/album caches —
// and so 'CacheBox' keeps exactly the keys it has today.

import 'dart:convert';

import 'package:hive/hive.dart';

class PodcastCache {
  static Box get _box => Hive.box('PodcastCache');

  /// Show pages change only when a new episode drops; a day is plenty and
  /// keeps a followed show's page instant offline.
  static const int showTtlMinutes = 1440;

  /// The Discover feed is editorial and rotates slowly.
  static const int discoverTtlMinutes = 360;

  static void write(String key, Object json) => _box.put(
      key,
      jsonEncode(
          {'data': json, 'ts': DateTime.now().millisecondsSinceEpoch}));

  /// Decoded payload if present and younger than [ttlMinutes], else null.
  static dynamic read(String key, int ttlMinutes) {
    final wrapper = _wrapper(key);
    if (wrapper == null) return null;
    final ts = (wrapper['ts'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > ttlMinutes * 60 * 1000) return null;
    return wrapper['data'];
  }

  /// True when [key] is missing or older than [ttlMinutes].
  static bool isStale(String key, int ttlMinutes) {
    final wrapper = _wrapper(key);
    if (wrapper == null) return true;
    final ts = (wrapper['ts'] as num?)?.toInt() ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ts > ttlMinutes * 60 * 1000;
  }

  /// Payload regardless of age — the offline / stale-while-revalidate path.
  static dynamic readAny(String key) => _wrapper(key)?['data'];

  static Map<String, dynamic>? _wrapper(String key) {
    final raw = _box.get(key);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() => _box.clear();
}
