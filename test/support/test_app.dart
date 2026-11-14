// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/app/app.dart';
import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:earloom/core/net/reachability.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/downloads/data/offline_providers.dart';
import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:earloom/features/local_library/data/providers.dart';
import 'package:earloom/features/player/player_controller.dart';
import 'package:earloom/features/player/ui/player_side_effects.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_downloads.dart';
import 'fake_player.dart';
import 'offline_covers.dart';

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

/// An in-memory LocalDb for widget tests, opened like [openTestGlobalDb].
Future<LocalDb> openTestLocalDb(WidgetTester tester) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = LocalDb(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.runAsync(() => db.select(db.localBooks).get());
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
  LocalDb? localDb,
  OfflineDb? offlineDb,
  Directory? storageRoot,
  GlobalDb? globalDb,
}) async {
  useOfflineCoverCache();
  final db = globalDb ?? await openTestGlobalDb(tester);
  final offline = offlineDb ?? await openTestOfflineDb(tester);
  onDb?.call(db);
  addTearDown(db.close);
  final local = localDb ?? await openTestLocalDb(tester);
  final storage = Directory.systemTemp.createTempSync('earloom_app_test_');
  addTearDown(() => storage.deleteSync(recursive: true));
  if (initialRoute != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = initialRoute;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        globalDbProvider.overrideWithValue(db),
        audioBackendProvider.overrideWithValue(FakeBackend()),
        accelerometerProvider.overrideWithValue(Stream.empty),
        // Account caches live in memory: no files, no path_provider.
        accountDbOpenerProvider.overrideWithValue(
          (_) => AccountDb(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)),
        ),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialOnboardedProvider.overrideWithValue(onboarded),
        secureStoreProvider.overrideWithValue(secureStore ?? MemorySecureStore()),
        localDbProvider.overrideWithValue(local),
        localStorageProvider.overrideWithValue(LocalStorage(storageRoot ?? Directory('${storage.path}/local'))),
        ...offlineTestOverrides(offline),
        ...overrides,
      ],
      child: const EarloomApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// The offline services without a network, a plugin or a disk: an
/// in-memory database, a server that always answers and no connectivity
/// events. Download manager tests override [downloadManagerProvider] or
/// [downloadTransportProvider] themselves.
List<Override> offlineTestOverrides(OfflineDb db, {Pinger? pinger}) => [
  offlineDbProvider.overrideWithValue(db),
  connectivityChangesProvider.overrideWithValue(const Stream<void>.empty()),
  pingerProvider.overrideWithValue(pinger ?? (_, _) async => true),
  supportDirProvider.overrideWithValue(() async => Directory.systemTemp),
  supportPathProvider.overrideWith((ref) async => Directory.systemTemp.path),
  freeSpaceProvider.overrideWith((ref) async => null),
];

/// Delivers a link the way the operating system does while the app runs.
Future<void> openLink(WidgetTester tester, String link) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': link, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// A phone-sized window (the default test window is 800 wide, which the
/// app treats as a tablet).
void usePhoneSize(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}
