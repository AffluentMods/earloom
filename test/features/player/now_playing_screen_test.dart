// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/player_controller.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/player/sleep_timer.dart';
import 'package:earloom/features/player/ui/mini_player.dart';
import 'package:earloom/features/player/ui/now_playing_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_player.dart';
import '../../support/test_app.dart';

const _book = ItemRef(LocalSource(), 'b1');

Future<PlayerEngine> _engineOf(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  return container.read(playerEngineProvider);
}

Future<void> _pumpWithBook(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The background drifts forever; with reduce motion it holds still, so
  // the screen can settle.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await pumpEarloom(
    tester,
    overrides: [
      bookResolverProvider.overrideWithValue(
        (ref, {startAt}) async =>
            (demoBook(ref, RecordingSink()), StartDecision(startAt ?? const Duration(minutes: 12))),
      ),
    ],
  );
  final engine = await _engineOf(tester);
  await tester.runAsync(() => engine.playItem(_book, autoplay: false));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the mini player appears with a loaded book and opens Now Playing', (tester) async {
    await _pumpWithBook(tester);
    final l10n = await loadL10n();
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text("The Clockmaker's Tide"), findsOneWidget);
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    // 12 minutes in: second file, chapter 2 of 3 (one chapter per file).
    expect(find.text(l10n.playerChapterOf(2, 3)), findsOneWidget);
    expect(find.byTooltip(l10n.playerSkipBack(15)), findsWidgets);
    expect(find.byTooltip(l10n.playerSkipForward(30)), findsOneWidget);
  });

  testWidgets('transport buttons move through the book', (tester) async {
    await _pumpWithBook(tester);
    final l10n = await loadL10n();
    final engine = await _engineOf(tester);
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);

    await tester.tap(find.byTooltip(l10n.playerSkipForward(30)));
    await settle(tester);
    expect(engine.value.position, const Duration(minutes: 12, seconds: 30));

    await tester.tap(find.byTooltip(l10n.playerNextChapter));
    await settle(tester);
    expect(engine.value.position, const Duration(minutes: 30));
    expect(find.text(l10n.playerChapterOf(3, 3)), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.playerPreviousChapter));
    await settle(tester);
    expect(engine.value.position, const Duration(minutes: 10));
  });

  testWidgets('the sleep sheet starts a timer that shows on the button', (tester) async {
    await _pumpWithBook(tester);
    final l10n = await loadL10n();
    final engine = await _engineOf(tester);
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);
    await tester.tap(find.byTooltip(l10n.playerSleepTimer));
    await settle(tester);
    await tester.tap(find.text(l10n.sleepMinutes(30)));
    await settle(tester);
    expect(engine.value.sleep, isA<SleepAfter>());
    expect(find.bySemanticsLabel(l10n.playerSleepRemaining('30:00')), findsOneWidget);
    engine.setSleepTimer(const SleepOff());
    await settle(tester);
  });

  testWidgets('the chapters sheet lists chapters and jumps to one', (tester) async {
    await _pumpWithBook(tester);
    final l10n = await loadL10n();
    final engine = await _engineOf(tester);
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);
    await tester.tap(find.byTooltip(l10n.playerChapters));
    await settle(tester);
    expect(find.text('Part 3'), findsWidgets);
    await tester.tap(find.text('Part 3').last);
    await settle(tester);
    expect(engine.value.position, const Duration(minutes: 30));
  });

  testWidgets('Now Playing and the mini player work at 200% text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpWithBook(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });

  testWidgets('Now Playing fits a 320 point wide phone', (tester) async {
    await _pumpWithBook(tester, size: const Size(320, 568));
    await tester.tap(find.text("The Clockmaker's Tide"));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });
}
