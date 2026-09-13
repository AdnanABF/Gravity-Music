// Settings → "Show Music / Podcasts switch". Off by default so the main screen
// matches the pre-Podcasts app; turning it off must never strand the user in
// Podcast Mode, since the switch is the only way back.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:saragama/podcast/controllers/podcast_mode_controller.dart';
import 'package:saragama/podcast/services/podcast_prefs.dart';
import 'package:saragama/podcast/ui/widgets/mode_switch.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('gm_switch_setting_test');
    Hive.init(dir.path);
    await Hive.openBox('PodcastBox');
  });

  setUp(() async => Hive.box('PodcastBox').clear());
  tearDown(() => Get.deleteAll(force: true));
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the switch is off by default', () {
    final c = Get.put(PodcastModeController());
    expect(c.switchEnabled.value, isFalse);
    expect(c.mode.value, AppMode.music);
  });

  test('turning the switch off returns to Music Mode', () {
    final c = Get.put(PodcastModeController());
    c.setSwitchEnabled(true);
    c.switchTo(AppMode.podcast);

    c.setSwitchEnabled(false);

    expect(c.mode.value, AppMode.music);
    expect(PodcastPrefs.switchEnabled, isFalse);
  });

  test('a saved podcast mode is not restored behind a disabled switch', () {
    PodcastPrefs.mode = AppMode.podcast;
    PodcastPrefs.switchEnabled = false;
    expect(Get.put(PodcastModeController()).mode.value, AppMode.music);
  });

  test('with the switch on, the saved mode comes back', () {
    PodcastPrefs.mode = AppMode.podcast;
    PodcastPrefs.switchEnabled = true;
    expect(Get.put(PodcastModeController()).mode.value, AppMode.podcast);
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('the pill and its dock slot render nothing while disabled',
      (tester) async {
    Get.put(PodcastModeController());
    await tester.pumpWidget(
        host(const Column(children: [ModeSwitchDockSlot(), ModeSwitchPill()])));
    expect(find.text('Podcasts'), findsNothing);
    expect(tester.getSize(find.byType(ModeSwitchDockSlot)).height, 0,
        reason: 'the dock must collapse back to its pre-Podcasts height');
  });

  testWidgets('enabling it from Settings shows the switch immediately',
      (tester) async {
    final c = Get.put(PodcastModeController());
    await tester.pumpWidget(host(const ModeSwitchDockSlot()));
    expect(find.text('Podcasts'), findsNothing);

    c.setSwitchEnabled(true);
    await tester.pump();

    expect(find.text('Podcasts'), findsOneWidget);
  });
}
