// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/theme/app_theme.dart';
import 'core/db/global_db.dart';
import 'core/db/local_db.dart';
import 'core/db/offline_db.dart';
import 'features/downloads/data/abs_download_manager.dart';
import 'features/downloads/data/download_rules.dart';
import 'features/downloads/data/offline_providers.dart';
import 'features/local_library/data/local_storage.dart';
import 'features/local_library/data/providers.dart';
import 'features/player/audio_handler.dart';
import 'features/player/bookmarks.dart';
import 'features/player/media_browser.dart';
import 'features/player/offline_session_recorder.dart';
import 'features/player/player_controller.dart';
import 'features/player/ui/player_widgets.dart';
import 'core/util/dev_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final globalDb = GlobalDb.open();
  final localDb = LocalDb.open();
  final offlineDb = OfflineDb.open();
  final support = await getApplicationSupportDirectory();
  final themeMode = AppThemeMode.fromName(await globalDb.readSetting(SettingKeys.themeMode));
  final onboarded =
      await globalDb.readSetting(SettingKeys.onboarded) == 'true' || (await globalDb.allAccounts()).isNotEmpty;
  final container = ProviderContainer(
    overrides: [
      globalDbProvider.overrideWithValue(globalDb),
      localDbProvider.overrideWithValue(localDb),
      offlineDbProvider.overrideWithValue(offlineDb),
      localStorageProvider.overrideWithValue(LocalStorage(Directory(p.join(support.path, 'local')))),
      initialThemeModeProvider.overrideWithValue(themeMode),
      initialOnboardedProvider.overrideWithValue(onboarded),
    ],
  );
  await _startPlayer(container);
  runApp(UncontrolledProviderScope(container: container, child: const EarloomApp()));
  unawaited(_startOffline(container, globalDb, offlineDb));
}

/// Downloads, the outbox and the server reachability. Runs after the first
/// frame: nothing here may delay start-up.
Future<void> _startOffline(ProviderContainer container, GlobalDb globalDb, OfflineDb offlineDb) async {
  try {
    // Nothing plays yet, so any open local session was cut off by a crash
    // or a kill: close it and queue it.
    await OfflineSessionRecorder.closeOrphans(offlineDb);
    final settings = await DownloadSettings.load(globalDb);
    final manager = container.read(downloadManagerProvider);
    if (manager is AbsDownloadManager) {
      await manager.start(wifiOnly: settings.wifiOnly);
    }
    final scheduler = container.read(syncSchedulerProvider)..start();
    // App foreground: check the server, flush, run the storage rules.
    AppLifecycleListener(
      onResume: () async {
        await scheduler.onForeground();
        await container.read(downloadRulesProvider).run();
      },
    );
    await scheduler.onForeground();
    await container.read(downloadRulesProvider).run();
  } on Object catch (e) {
    devLog('Offline services did not start: $e');
  }
}

/// Connects the player engine to the lock screen, notification, headset
/// and car controls. The engine runs whether or not this succeeds.
Future<void> _startPlayer(ProviderContainer container) async {
  final l10n = deviceL10n();
  final engine = container.read(playerEngineProvider);
  // The last book must be known before the first route: the Resume
  // shortcut and earloom://player depend on it.
  await engine.restore();
  final prefs = await container.read(playerStoreProvider).loadPrefs();
  Future<void> bookmarkFromNotification() async {
    final s = engine.value;
    final now = s.now;
    if (now == null) return;
    final chapter = s.chapter;
    final title = chapter == null
        ? formatClock(s.position)
        : l10n.bookmarkDefaultTitle(chapter.title, formatClock(s.position - chapter.start));
    await container.read(bookmarkServiceProvider).add(now.ref, s.position, title);
  }

  try {
    await AudioService.init(
      builder: () => AppAudioHandler(
        engine,
        onBookmark: bookmarkFromNotification,
        bookmarkLabel: l10n.playerBookmark,
        speedLabel: l10n.playerSpeed,
        sleepLabel: (m) => l10n.playerSleepRemaining(l10n.durationMinutes(m)),
        browser: container.read(mediaBrowserProvider),
      ),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.affluentlabs.earloom.playback',
        androidNotificationChannelName: l10n.playerNotificationChannel,
        androidNotificationIcon: 'drawable/ic_stat_earloom',
        fastForwardInterval: prefs.skipForward,
        rewindInterval: prefs.skipBack,
        androidBrowsableRootExtras: MediaBrowser.rootExtras,
      ),
    );
  } on Object catch (e) {
    // Without the service, audio still plays while the app is open.
    devLog('Audio service did not start: $e');
  }
}
