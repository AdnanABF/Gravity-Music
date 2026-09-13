// Parsers for the shapes YouTube Music actually returns on its podcast
// endpoints. Durations arrive as prose ("2 hr 16 min"), not the "m:ss" music
// uses, and publish dates arrive as relative labels — both are load-bearing:
// a duration of zero breaks resume ("18 min left"), and an unparsed date
// silently flattens the recommender's recency ranking.

import 'package:flutter_test/flutter_test.dart';
import 'package:saragama/podcast/services/yt_podcast_api.dart';

void main() {
  group('parseDuration', () {
    test('prose form, as podcast pages render it', () {
      expect(YtPodcastApi.parseDuration('2 hr 16 min'),
          const Duration(hours: 2, minutes: 16));
      expect(YtPodcastApi.parseDuration('45 min'), const Duration(minutes: 45));
      expect(YtPodcastApi.parseDuration('1 hr'), const Duration(hours: 1));
      expect(YtPodcastApi.parseDuration('38 sec'), const Duration(seconds: 38));
      expect(YtPodcastApi.parseDuration('1 hour 5 minutes'),
          const Duration(hours: 1, minutes: 5));
    });

    test('the bullet YouTube prefixes durationText with is stripped', () {
      expect(YtPodcastApi.parseDuration(' • 2 hr 16 min'),
          const Duration(hours: 2, minutes: 16));
    });

    test('clock form still parses, since some rows use it', () {
      expect(YtPodcastApi.parseDuration('1:02:33'),
          const Duration(hours: 1, minutes: 2, seconds: 33));
      expect(YtPodcastApi.parseDuration('58:21'),
          const Duration(minutes: 58, seconds: 21));
    });

    test('unparseable text yields zero rather than throwing', () {
      expect(YtPodcastApi.parseDuration(''), Duration.zero);
      expect(YtPodcastApi.parseDuration('LIVE'), Duration.zero);
      expect(YtPodcastApi.parseDuration('coming soon'), Duration.zero);
    });
  });

  group('parseRelativeDate', () {
    final now = DateTime(2026, 3, 10, 12);

    test('relative labels', () {
      expect(YtPodcastApi.parseRelativeDate('3d ago', now: now),
          DateTime(2026, 3, 7, 12));
      expect(YtPodcastApi.parseRelativeDate('2 hours ago', now: now),
          DateTime(2026, 3, 10, 10));
      expect(YtPodcastApi.parseRelativeDate('1 week ago', now: now),
          DateTime(2026, 3, 3, 12));
    });

    test('absolute labels', () {
      expect(YtPodcastApi.parseRelativeDate('Aug 27, 2024', now: now),
          DateTime(2024, 8, 27));
      // No year means this year…
      expect(YtPodcastApi.parseRelativeDate('Jan 5', now: now),
          DateTime(2026, 1, 5));
    });

    test('a bare month/day that would be in the future means LAST year', () {
      // "Aug 27" seen in March 2026 is 2025 — treating it as 2026 would sort
      // an old episode above everything new.
      expect(YtPodcastApi.parseRelativeDate('Aug 27', now: now),
          DateTime(2025, 8, 27));
    });

    test('unrecognised text is null, not an exception', () {
      expect(YtPodcastApi.parseRelativeDate('', now: now), isNull);
      expect(YtPodcastApi.parseRelativeDate('recently', now: now), isNull);
    });
  });
}
