// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Launches the real app on a device, emulator or simulator and walks the
// Phase 0 shell: tabs, the theme switch, the design previews and deep links.
// Screenshots go to build/device-screenshots/ when run through the driver:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_launch_test.dart
//
// It uses the real on-device database, so it also proves that SQLite and the
// bundled fonts and covers load on the platform.

import 'dart:io';

import 'package:earloom/app/debug/debug_hub_screen.dart';
import 'package:earloom/app/debug/design_item_preview.dart';
import 'package:earloom/app/debug/design_player_preview.dart';
import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:earloom/features/library/ui/library_screen.dart';
import 'package:earloom/features/player/ui/now_playing_screen.dart';
import 'package:earloom/features/search/ui/search_screen.dart';
import 'package:earloom/features/you/ui/you_screen.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:earloom/main.dart' as app;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app launches and the Phase 0 shell works on this device', (tester) async {
    await app.main();
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // In-app screenshots only where they are cheap. On Android the screenshot
    // API first has to move Flutter onto an image view, which a software
    // rendered CI emulator could not keep up with (it dropped off mid-run).
    // There, tool/ci/device_check_android.sh takes screenshots with adb.
    Future<void> shot(String name) async {
      await settle(tester);
      if (Platform.isAndroid) return;
      await binding.takeScreenshot('${Platform.operatingSystem}_$name');
    }

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));
    final bar = find.byType(NavigationBar);
    Future<void> tab(String label) async {
      await tester.tap(find.descendant(of: bar, matching: find.text(label)));
      await settle(tester);
    }

    await shot('01_home');

    // Every tab opens its screen.
    await tab(l10n.tabLibrary);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tab(l10n.tabSearch);
    expect(find.byType(SearchScreen), findsOneWidget);
    await tab(l10n.tabYou);
    expect(find.byType(YouScreen), findsOneWidget);

    // Developer screens, then the theme switch.
    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await settle(tester);
    expect(find.byType(DebugHubScreen), findsOneWidget);

    Brightness brightness() => Theme.of(tester.element(find.byType(DebugHubScreen))).brightness;
    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(brightness(), Brightness.dark);
    await shot('02_debug_hub_dark');

    // Design previews: first book in dark, then light, then a second book.
    await openPreview(tester, item: true, book: 0);
    expect(find.byType(DesignItemPreview), findsOneWidget);
    await shot('03_item_dark');
    await back(tester);

    await openPreview(tester, item: false, book: 0);
    expect(find.byType(DesignPlayerPreview), findsOneWidget);
    await shot('04_player_dark');
    await back(tester);

    await tester.tap(find.text('Light'));
    await settle(tester);
    expect(brightness(), Brightness.light);
    await openPreview(tester, item: true, book: 1);
    await shot('05_item_light');
    await back(tester);

    await tester.tap(find.text('AMOLED'));
    await settle(tester);
    await openPreview(tester, item: false, book: 6);
    await shot('06_player_amoled');
    await back(tester);

    // Leave the device on the system theme for the next run.
    await tester.tap(find.text('System'));
    await settle(tester);

    // Deep links, delivered the way the operating system hands them over.
    await openLink(tester, 'earloom://item/test');
    expect(tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId, 'test');
    await shot('07_deep_link_item');

    await openLink(tester, 'earloom://player');
    expect(find.byType(NowPlayingScreen), findsOneWidget);

    await openLink(tester, 'earloom://settings/delete-everything');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ItemDetailScreen), findsNothing);
  });
}

/// Lets real async work finish (image decoding, database reads), then waits
/// for every animation to end.
Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> openPreview(WidgetTester tester, {required bool item, required int book}) async {
  final tooltip = item ? 'Item detail preview' : 'Now Playing preview';
  final button = find.byTooltip(tooltip).at(book);
  await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(button);
  // The cover scheme comes from decoding the cover: give it real time.
  await Future<void>.delayed(const Duration(seconds: 2));
  await settle(tester);
}

Future<void> back(WidgetTester tester) async {
  final close = find.byTooltip('Close');
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
  } else {
    await tester.pageBack();
  }
  await settle(tester);
}

Future<void> openLink(WidgetTester tester, String link) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': link, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await settle(tester);
}
