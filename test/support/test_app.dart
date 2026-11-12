// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:drift/native.dart';
import 'package:earloom/app/app.dart';
import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Pumps the whole app with an in-memory settings database.
///
/// Returns the database so a test can check what was saved.
Future<GlobalDb> pumpEarloom(
  WidgetTester tester, {
  AppThemeMode themeMode = AppThemeMode.system,
  String? initialRoute,
}) async {
  final db = GlobalDb(NativeDatabase.memory());
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
