// The isolation contract. Podcast Mode plays through the SAME audio handler as
// music (there is only one per app — it owns the notification and Android's
// foreground service), so a handful of music-side listeners see episodes go
// past. Three guards keep them from acting on one, and all three key off the
// domain marker tested here.
//
// If this file fails, podcast data is leaking into music state.

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saragama/podcast/models/podcast_episode.dart';
import 'package:saragama/services/search_service.dart';
import 'package:saragama/shared/media_domain.dart';
import 'package:saragama/ui/ui_helpers.dart';

PodcastEpisode _episode() => const PodcastEpisode(
      id: 'MGxcosNuC8k',
      title: 'Andrew Huberman: My Exact Routine',
      browseId: 'MPEDMGxcosNuC8k',
      showId: 'MPSPPL22egh',
      showTitle: 'The Diary Of A CEO',
      artwork: 'https://i.ytimg.com/vi/MGxcosNuC8k/hqdefault.jpg',
      showArtwork: 'https://i.ytimg.com/pl_c/PL22egh/studio_square.jpg',
      duration: Duration(hours: 2, minutes: 16),
      publishedLabel: '3d ago',
    );

const _song = SearchResult(
  title: 'Thakilu Pukilu',
  videoId: 'abc123',
  artists: ['M. G. Sreekumar'],
  thumbnail: 'https://lh3.googleusercontent.com/x=w96-h96-l90-rj',
  duration: '4:20',
);

void main() {
  group('domain marker', () {
    test('an episode MediaItem is marked as a podcast', () {
      expect(isPodcastItem(_episode().toMediaItem()), isTrue);
    });

    test('a music MediaItem is NOT — so every music guard is a no-op', () {
      expect(isPodcastItem(_song.toMediaItem()), isFalse);
    });

    test('null and extras-less items read as music (the safe default)', () {
      expect(isPodcastItem(null), isFalse);
      expect(isPodcastItem(const MediaItem(id: 'x', title: 'x')), isFalse);
      expect(
          isPodcastItem(const MediaItem(id: 'x', title: 'x', extras: {})),
          isFalse);
    });
  });

  group('episode MediaItem', () {
    test("extras['url'] is present and MUTABLE — the handler writes into it", () {
      final item = _episode().toMediaItem();
      expect(item.extras!['url'], '');
      // A const map here would throw at play time and hang the episode on
      // "loading" forever; this is the same trap ui_helpers documents.
      expect(() => item.extras!['url'] = 'https://stream', returnsNormally);
      expect(item.extras!['url'], 'https://stream');
    });

    test('round-trips back into an episode', () {
      final original = _episode();
      final restored = PodcastEpisode.fromMediaItem(original.toMediaItem());
      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.showId, original.showId);
      expect(restored.showTitle, original.showTitle);
      expect(restored.artwork, original.artwork);
      expect(restored.duration, original.duration);
    });

    test('a music item never round-trips into an episode', () {
      expect(PodcastEpisode.fromMediaItem(_song.toMediaItem()), isNull);
    });

    test('the series is what shows on the lockscreen, not a fake artist', () {
      final item = _episode().toMediaItem();
      expect(item.artist, 'The Diary Of A CEO');
      expect(item.album, 'The Diary Of A CEO');
    });
  });

  group('artwork', () {
    test('episode art is the permanent frame — no ThumbUtil square rewrite',
        () {
      final item = _episode().toMediaItem();
      expect(item.artUri.toString(),
          'https://i.ytimg.com/vi/MGxcosNuC8k/hq720.jpg');
      expect(item.artUri.toString(), isNot(contains('=w')));
    });

    test('falls back to the show cover when the episode has none', () {
      final e = _episode().copyWith(artwork: '');
      expect(e.displayArtwork, e.showArtwork);
    });

    test('music items still get the hi-res square art they always did', () {
      final item = _song.toMediaItem();
      expect(item.artUri.toString(), contains('=w544-h544'));
    });
  });
}
