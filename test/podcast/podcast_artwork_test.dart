// The artwork rule that separates podcasts from music: podcast art is NOT
// square, so it must never be pushed through the `=wN-hN` box rewrite that
// ThumbUtil applies to album covers. These tests pin that boundary — a
// regression here is exactly the "podcast art got cropped" bug.

import 'package:flutter_test/flutter_test.dart';
import 'package:saragama/podcast/services/podcast_artwork.dart';
import 'package:saragama/services/thumb_util.dart';

void main() {
  // Real URLs, as returned by the endpoints.
  const episodeArt =
      'https://i.ytimg.com/vi/MGxcosNuC8k/hqdefault.jpg?sqp=-oaymwEWCJADEOEBIAQqCggAEOADGC0guwJIWg&rs=AMzJL3m';
  const showCover =
      'https://i.ytimg.com/pl_c/PL22egh3ok4cP0T7UZRmP6TMLErZYWMN-l/studio_square_thumbnail.jpg?sqp=CM7Z&rs=AMzJL3m';
  const creatorAvatar =
      'https://yt3.ggpht.com/JHCZDz37bsTmwoE1o4LEodF5vhsHfk29kCEauDTFr27=s96-c-k-c0x00000000-no-cc-rj-rp';

  group('PodcastArtwork.sized', () {
    test('signed i.ytimg URLs are returned verbatim', () {
      // Their sqp/rs signature already encodes the crop; appending a size
      // param does nothing at best and breaks the signature at worst.
      expect(PodcastArtwork.sized(episodeArt, PodcastArtwork.listThumb),
          episodeArt);
      expect(PodcastArtwork.sized(showCover, PodcastArtwork.hero), showCover);
    });

    test('resizable Google URLs use =sN, which preserves aspect ratio', () {
      final out = PodcastArtwork.sized(creatorAvatar, 240);
      expect(out, contains('=s240'));
      expect(out, isNot(contains('=s96')));
      // The flags after the size are preserved.
      expect(out, contains('-c-k-c0x00000000'));
    });

    test('never emits the square =wN-hN box that music art uses', () {
      for (final url in [episodeArt, showCover, creatorAvatar]) {
        for (final size in [
          PodcastArtwork.listThumb,
          PodcastArtwork.card,
          PodcastArtwork.hero
        ]) {
          expect(PodcastArtwork.sized(url, size), isNot(matches(r'=w\d+-h\d+')),
              reason: 'podcast art must never be requested as a fixed box');
        }
      }
    });

    test('empty stays empty', () {
      expect(PodcastArtwork.sized('', 96), '');
    });
  });

  group('music artwork is untouched by any of this', () {
    test('ThumbUtil still produces its square box for album art', () {
      const albumArt =
          'https://lh3.googleusercontent.com/abc123=w60-h60-l90-rj';
      expect(ThumbUtil.get(albumArt, ThumbnailSize.tile),
          'https://lh3.googleusercontent.com/abc123=w96-h96-l90-rj');
      expect(ThumbUtil.get(albumArt, ThumbnailSize.art),
          'https://lh3.googleusercontent.com/abc123=w544-h544-l90-rj');
    });
  });

  group('presumedRatio', () {
    test('video frames are treated as 16:9 before they resolve', () {
      expect(PodcastArtwork.presumedRatio(episodeArt), closeTo(16 / 9, 0.001));
    });

    test('covers and avatars default to square', () {
      expect(PodcastArtwork.presumedRatio(showCover), 1.0);
      expect(PodcastArtwork.presumedRatio(creatorAvatar), 1.0);
    });
  });

  test('clampRatio keeps a freak banner from blowing out a row', () {
    expect(PodcastArtwork.clampRatio(3.5), 2.0);
    expect(PodcastArtwork.clampRatio(0.2), 0.6);
    expect(PodcastArtwork.clampRatio(1.0), 1.0);
  });

  // Signatures on i.ytimg URLs rotate on EVERY response and old ones 404
  // (verified live). These pin the two fixes for that.
  group('signature-proof artwork', () {
    const signedA =
        'https://i.ytimg.com/vi/MGxcosNuC8k/hqdefault.jpg?sqp=-oaymwEWCJADEOEBIAQqCggAEOADGC0guwJIWg&rs=AAA';
    const signedB =
        'https://i.ytimg.com/vi/MGxcosNuC8k/hq720.jpg?sqp=-oaymwEKCKAGEMIDIABIWg&rs=BBB';

    test('episode frames become one permanent unsigned URL', () {
      const want = 'https://i.ytimg.com/vi/MGxcosNuC8k/hq720.jpg';
      expect(PodcastArtwork.canonical(signedA), want);
      expect(PodcastArtwork.canonical(signedB), want);
      expect(PodcastArtwork.canonical(want), want, reason: 'idempotent');
    });

    test('show covers are NOT rewritten — they 404 without a signature', () {
      expect(PodcastArtwork.canonical(showCover), showCover);
    });

    test('non-YouTube URLs pass through untouched', () {
      expect(PodcastArtwork.canonical(creatorAvatar), creatorAvatar);
      expect(PodcastArtwork.canonical(''), '');
    });

    test('a frame falls back to the always-present 16:9 mqdefault', () {
      expect(PodcastArtwork.frameFallbackFor(signedA),
          'https://i.ytimg.com/vi/MGxcosNuC8k/mqdefault.jpg');
      expect(
          PodcastArtwork.frameFallbackFor(
              'https://i.ytimg.com/vi/MGxcosNuC8k/mqdefault.jpg'),
          isNull,
          reason: 'no fallback loop');
      expect(PodcastArtwork.frameFallbackFor(showCover), isNull);
    });

    test('the cache key ignores the rotating signature', () {
      const coverNow =
          'https://i.ytimg.com/pl_c/PL22egh/studio_square_thumbnail.jpg?sqp=CKLZ&rs=one';
      const coverLater =
          'https://i.ytimg.com/pl_c/PL22egh/studio_square_thumbnail.jpg?sqp=CM7Z&rs=two';
      expect(PodcastArtwork.cacheKey(coverNow),
          PodcastArtwork.cacheKey(coverLater),
          reason: 'bytes cached on one visit must serve the next');
      expect(PodcastArtwork.cacheKey(creatorAvatar), creatorAvatar);
    });
  });
}
