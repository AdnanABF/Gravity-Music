// Guards the trap that blanked the Library: an Obx whose closure reads no
// observable throws ObxError, and a RELEASE build paints that as an empty grey
// rectangle instead of the list. Passing an RxList straight to a child widget
// as a plain List reads nothing in the closure, so it looks correct and fails
// silently off-debug.
//
// Pumping the real screen is the only way to catch it: the mistake is invisible
// to the analyzer and to any pure-Dart test.

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:saragama/podcast/controllers/podcast_library_controller.dart';
import 'package:saragama/podcast/controllers/podcast_player_controller.dart';
import 'package:saragama/podcast/models/podcast_show.dart';
import 'package:saragama/podcast/services/podcast_library_service.dart';
import 'package:saragama/podcast/ui/podcast_library_screen.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('gm_podcast_ui_test');
    Hive.init(dir.path);
    await Hive.openBox('PodcastBox');
    await Hive.openBox('PodcastHistory');
  });

  setUp(() async {
    await Hive.box('PodcastBox').clear();
    await Hive.box('PodcastHistory').clear();
    Get.put(PodcastPlayerController(
        audioHandler: BaseAudioHandler(), observeEngine: false));
    Get.put(PodcastLibraryController());
  });

  tearDown(() async {
    // Dispose the controllers before the next test re-registers them.
    await Get.deleteAll(force: true);
  });

  tearDownAll(() {
    // Deliberately no `Hive.close()`: under the widget-test binding it never
    // settles and the harness hangs on shutdown. The boxes live in a temp dir
    // that goes away with the process, so there is nothing to flush.
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  testWidgets('every Library tab builds without an Obx error', (tester) async {
    await pump(tester, const PodcastLibraryScreen());

    // Each tab must render on its own — the bug only fired on the three that
    // passed their RxList through untouched.
    for (final label in [
      'Following',
      'Saved',
      'Downloaded',
      'Recently Played',
      'Completed'
    ]) {
      await tester.tap(find.textContaining(label).first);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'the "$label" tab threw while building');
      // An ObxError leaves nothing but the error widget, so the empty state's
      // presence is the proof the list actually built.
      expect(find.byType(Icon), findsWidgets,
          reason: '"$label" rendered no content at all');
    }
  });

  testWidgets('Following renders its empty state, not a blank box',
      (tester) async {
    await pump(tester, const PodcastLibraryScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Not following anything yet'), findsOneWidget);
  });

  testWidgets('a followed show reaches the list', (tester) async {
    PodcastLibraryService.follow(
        const PodcastShow(id: 's1', title: 'The Diary Of A CEO', author: 'DOAC'));
    await pump(tester, const PodcastLibraryScreen());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('The Diary Of A CEO'), findsOneWidget);
  });
}
