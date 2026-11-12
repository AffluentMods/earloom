// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/debug/cover_colors_screen.dart';
import 'package:earloom/app/debug/debug_hub_screen.dart';
import 'package:earloom/app/debug/debug_routes.dart';
import 'package:earloom/app/debug/demo_books.dart';
import 'package:earloom/app/debug/design_item_preview.dart';
import 'package:earloom/app/debug/design_player_preview.dart';
import 'package:earloom/features/you/ui/you_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

void main() {
  // Real fonts, so text takes the room it takes on a device.
  setUpAll(loadAppFonts);

  // A phone-sized window, so the previews lay out the way they do on a device.
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('the You tab opens the developer screens in a debug build', (tester) async {
    usePhone(tester);
    await pumpEarloom(tester);
    final l10n = await loadL10n();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(l10n.tabYou)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(YouScreen), matching: find.byIcon(Icons.bug_report_outlined)));
    await tester.pumpAndSettle();
    expect(find.byType(DebugHubScreen), findsOneWidget);
  });

  testWidgets('every developer screen builds and lays out without errors', (tester) async {
    usePhone(tester);
    await pumpEarloom(tester);
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));

    Future<void> open(String location, Type screen) async {
      router.go(location);
      // Covers decode on real time, which a widget test does not advance:
      // a few frames are enough to build and lay out the screen.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(screen), findsOneWidget, reason: location);
      expect(tester.takeException(), isNull, reason: location);
    }

    await open(DebugRoutes.hub, DebugHubScreen);
    await open(DebugRoutes.colors, CoverColorsScreen);
    for (var i = 0; i < demoBooks.length; i++) {
      await open(DebugRoutes.designItem(i), DesignItemPreview);
      await open(DebugRoutes.designPlayer(i), DesignPlayerPreview);
    }
    // An out-of-range book index is clamped, not a crash.
    await open(DebugRoutes.designItem(999), DesignItemPreview);
  });

  testWidgets('the previews fit the smallest phones without overflowing', (tester) async {
    // 320 points wide: an iPhone SE (1st gen) and the default CI emulator,
    // where the Now Playing controls once overflowed by 36 pixels.
    tester.view.physicalSize = const Size(320, 568) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pumpEarloom(tester);
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    for (var i = 0; i < demoBooks.length; i++) {
      for (final location in [DebugRoutes.designItem(i), DebugRoutes.designPlayer(i)]) {
        router.go(location);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: location);
      }
    }
  });

  testWidgets('the previews survive large text without overflowing', (tester) async {
    usePhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpEarloom(tester);
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    for (final location in [DebugRoutes.designItem(4), DebugRoutes.designPlayer(4)]) {
      router.go(location);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: location);
    }
  });
}
