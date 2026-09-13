// podcast/services/podcast_artwork.dart
//
// Podcast artwork sizing. Deliberately NOT ThumbUtil.
//
// ThumbUtil is correct for music and must stay untouched: album art is square
// by definition, so rewriting a Google CDN URL to `=w96-h96-…` is lossless
// there. Podcast art is not square. YT Music serves:
//
//   show covers    i.ytimg.com/pl_c/<PL>/studio_square_thumbnail.jpg?sqp=…
//                  square-ish, up to 544×544
//   episode art    i.ytimg.com/vi/<id>/hqdefault.jpg?sqp=…
//                  16:9 — 400×225, 800×450, 853×479
//   creator art    yt3.ggpht.com/…=s96-c-k-…
//                  square avatars
//
// Two rules follow:
//
//  1. The `sqp`/`rs` signed parameters on an i.ytimg URL encode the crop the
//     server already applied. Appending `=wN-hN` to one does nothing at best
//     and breaks the signature at worst — so those URLs are returned VERBATIM
//     and the cost is controlled at *decode* time instead (memCacheWidth),
//     which is where the memory actually goes.
//
//  2. Only genuinely resizable hosts (`ggpht`/`googleusercontent` with an
//     `=sN` segment) are rewritten, and then with `=sN` — the "longest edge"
//     form, which preserves aspect ratio — never `=wN-hN`, which asks the CDN
//     for a fixed box.
//
// Nothing in this file is reachable from music code, and it imports none.

class PodcastArtwork {
  /// Render tiers, in logical pixels of the longest edge.
  static const int listThumb = 96;   // episode/show rows
  static const int card = 240;       // carousel + grid cards
  static const int hero = 640;       // show header, full player

  /// Returns a URL sized for a target render width where that is safe, and the
  /// original otherwise. Never crops, never forces a square box.
  static String sized(String url, int targetPx) {
    if (url.isEmpty) return url;

    // Signed YouTube image URLs: leave exactly as served.
    if (url.contains('i.ytimg.com')) return url;

    // Avatars and other Google-hosted art expose an `=sN` size segment.
    // `=sN` scales the LONGEST edge and preserves the aspect ratio; the
    // trailing flags (`-c-k-…`) are kept so cropping behaviour is unchanged
    // from what the server chose.
    final s = RegExp(r'=s(\d+)').firstMatch(url);
    if (s != null) {
      return url.replaceFirst(RegExp(r'=s\d+'), '=s$targetPx');
    }

    // A googleusercontent URL with no size segment can take one. `=sN` again,
    // NOT the `=wN-hN` box ThumbUtil uses for square album art.
    if ((url.contains('googleusercontent.com') || url.contains('ggpht.com')) &&
        !url.contains('=')) {
      return '$url=s$targetPx';
    }

    return url;
  }

  // ── Stability ────────────────────────────────────────────────────────────
  //
  // Measured against live responses: the `sqp`/`rs` signature on i.ytimg
  // URLs is regenerated on EVERY response, and an old signature eventually
  // 404s. Two consequences, two fixes:
  //
  //  • Episode frames (`/vi/<id>/…`) work unsigned forever, so they are
  //    rewritten to a permanent URL — [canonical].
  //  • Show covers (`/pl_c/<PL>/studio_square_thumbnail.jpg`) 404 WITHOUT a
  //    signature, so they can't be rewritten. They are cached under a key
  //    that ignores the signature — [cacheKey] — so the bytes downloaded once
  //    keep being served after the URL itself has changed or expired.

  static final _videoFrameRe =
      RegExp(r'i\.ytimg\.com/vi(?:_webp)?/([\w-]{6,})/');

  /// Permanent form of [url]. Episode frames → unsigned 1280×720 `hq720.jpg`;
  /// everything else unchanged. Safe to call on already-canonical URLs and on
  /// URLs stored by older builds, which is how existing history heals itself.
  static String canonical(String url) {
    final m = _videoFrameRe.firstMatch(url);
    if (m == null) return url;
    return 'https://i.ytimg.com/vi/${m.group(1)}/hq720.jpg';
  }

  /// A second URL to try when [url] fails, or null. `hq720` doesn't exist for
  /// videos never published in HD; `mqdefault` (320×180) exists for every
  /// video and is also true 16:9 — unlike `hqdefault`, which is letterboxed
  /// 4:3 and would bring back the black bars this pipeline avoids.
  static String? frameFallbackFor(String url) {
    final m = _videoFrameRe.firstMatch(url);
    if (m == null || url.endsWith('/mqdefault.jpg')) return null;
    return 'https://i.ytimg.com/vi/${m.group(1)}/mqdefault.jpg';
  }

  /// Image-cache key for [url] that is stable across YouTube's rotating
  /// signatures: scheme + host + path for i.ytimg, the URL itself otherwise.
  static String cacheKey(String url) {
    if (!url.contains('i.ytimg.com')) return url;
    final q = url.indexOf('?');
    return q < 0 ? url : url.substring(0, q);
  }

  /// Pixel budget for decoding [url] at [logicalWidth] on this display.
  /// Capped so a 1280px episode frame in a 96px row doesn't hold a full-size
  /// bitmap in the image cache.
  static int decodeWidth(double logicalWidth, double devicePixelRatio) =>
      (logicalWidth * devicePixelRatio).round().clamp(64, 1600);

  /// Aspect ratio to lay a piece of artwork out at before its real dimensions
  /// are known, inferred from the URL shape. Episode frames are 16:9; show
  /// covers and avatars are square. Only a first guess — [PodcastArtworkImage]
  /// re-lays-out at the true ratio once the image resolves.
  static double presumedRatio(String url) {
    if (url.contains('/vi/') || url.contains('hqdefault') ||
        url.contains('hq720')) {
      return 16 / 9;
    }
    return 1.0;
  }

  /// Clamp for natural-ratio layout, so a freak 3:1 banner or a tall poster
  /// can't blow out a row or a header.
  static double clampRatio(double ratio) => ratio.clamp(0.6, 2.0);
}
