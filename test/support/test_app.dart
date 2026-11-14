// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:earloom/app/app.dart';
import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// English strings for assertions, so tests never hardcode UI copy.
Future<AppLocalizations> loadL10n() => AppLocalizations.delegate.load(const Locale('en'));

/// Loads the bundled fonts so text renders with real glyphs and metrics
/// instead of the test font's boxes.
Future<void> loadAppFonts() async {
  Future<ByteData> read(String path) async => ByteData.sublistView(await File(path).readAsBytes());
  await (FontLoader('Inter')
        ..addFont(read('assets/fonts/Inter-Variable.ttf'))
        ..addFont(read('assets/fonts/Inter-Italic-Variable.ttf')))
      .load();
  await (FontLoader('Newsreader')
        ..addFont(read('assets/fonts/Newsreader-Variable.ttf'))
        ..addFont(read('assets/fonts/Newsreader-Italic-Variable.ttf')))
      .load();
  // Material Icons, from the Flutter SDK cache, for screenshots.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(read(icons.path))).load();
    }
  }
}

/// An in-memory GlobalDb that works inside widget tests.
///
/// drift must be opened outside the test's fake clock (the first query opens
/// SQLite), and its streams must close synchronously, or watching a query
/// hangs the test. Pair with [settle] instead of pumpAndSettle whenever the
/// screen reads the database.
Future<GlobalDb> openTestGlobalDb(WidgetTester tester) async {
  final db = GlobalDb(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.runAsync(() => db.readSetting('warm-up'));
  addTearDown(() => tester.runAsync(db.close));
  return db;
}

/// Lets real asynchronous work (database queries, stream updates, image
/// decoding) finish between frames, then waits for animations to end.
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    // Advance the fake clock too: HTTP clients arm timers that must tick.
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Pumps the whole app with an in-memory settings database.
///
/// Returns the database so a test can check what was saved.
Future<GlobalDb> pumpEarloom(
  WidgetTester tester, {
  AppThemeMode themeMode = AppThemeMode.system,
  String? initialRoute,
  bool onboarded = true,
  List<Override> overrides = const [],
  void Function(GlobalDb db)? onDb,
  SecureStore? secureStore,
}) async {
  final db = await openTestGlobalDb(tester);
  onDb?.call(db);
  addTearDown(db.close);
  if (initialRoute != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = initialRoute;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        globalDbProvider.overrideWithValue(db),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialOnboardedProvider.overrideWithValue(onboarded),
        secureStoreProvider.overrideWithValue(secureStore ?? MemorySecureStore()),
        ...overrides,
      ],
      child: const EarloomApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Delivers a link the way the operating system does while the app runs.
Future<void> openLink(WidgetTester tester, String link) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': link, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}
