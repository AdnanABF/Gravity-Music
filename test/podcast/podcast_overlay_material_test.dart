// Music Mode's desktop shell layers the Podcasts pill and the podcast player
// dock in a Stack OUTSIDE the music Scaffold, so they have no Material
// ancestor. Text there inherits no style, and Flutter renders it with its
// yellow double-underline fallback. These widgets must carry their own.
//
// Pumped deliberately WITHOUT MaterialApp/Scaffold to reproduce that spot.

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:saragama/podcast/controllers/podcast_mode_controller.dart';
import 'package:saragama/podcast/controllers/podcast_player_controller.dart';
import 'package:saragama/podcast/models/podcast_episode.dart';
import 'package:saragama/podcast/ui/widgets/mode_switch.dart';
import 'package:saragama/podcast/ui/widgets/podcast_mini_player.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('gm_overlay_test');
    Hive.init(dir.path);
    await Hive.openBox('PodcastBox');
    await Hive.openBox('PodcastHistory');
  });

  setUp(() {
    Get.put(PodcastModeController()).setSwitchEnabled(true);
    Get.put(PodcastPlayerController(
        audioHandler: BaseAudioHandler(), observeEngine: false));
  });

  tearDown(() => Get.deleteAll(force: true));

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A bare tree: text direction and media query, but no Material anywhere.
  Widget bare(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [Positioned(left: 0, right: 0, bottom: 0, child: child)]),
        ),
      );

  void expectEveryTextUnderMaterial(WidgetTester tester) {
    final texts = find.byType(Text);
    expect(texts, findsWidgets);
    for (final e in texts.evaluate()) {
      final hasMaterial =
          e.findAncestorWidgetOfExactType<Material>() != null;
      expect(hasMaterial, isTrue,
          reason: '"${(e.widget as Text).data}" has no Material ancestor '
              'and would render with the yellow underline');
    }
  }

  testWidgets('the mode switch pill styles its own text', (tester) async {
    await tester.pumpWidget(bare(const ModeSwitchPill()));
    expectEveryTextUnderMaterial(tester);
  });

  testWidgets('the desktop podcast dock styles its own text', (tester) async {
    Get.find<PodcastPlayerController>().currentEpisode.value =
        const PodcastEpisode(
            id: 'e1', title: 'An episode', showTitle: 'A show');
    await tester.pumpWidget(bare(const PodcastDesktopDock()));
    await tester.pump();
    expectEveryTextUnderMaterial(tester);
  });
}
