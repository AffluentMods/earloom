// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

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
import 'features/local_library/data/local_storage.dart';
import 'features/local_library/data/providers.dart';
import 'features/player/audio_handler.dart';
import 'features/player/bookmarks.dart';
import 'features/player/player_controller.dart';
import 'features/player/ui/player_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final globalDb = GlobalDb.open();
  final localDb = LocalDb.open();
  final support = await getApplicationSupportDirectory();
  final themeMode = AppThemeMode.fromName(await globalDb.readSetting(SettingKeys.themeMode));
  final onboarded =
      await globalDb.readSetting(SettingKeys.onboarded) == 'true' || (await globalDb.allAccounts()).isNotEmpty;
  final container = ProviderContainer(
    overrides: [
      globalDbProvider.overrideWithValue(globalDb),
      localDbProvider.overrideWithValue(localDb),
      localStorageProvider.overrideWithValue(LocalStorage(Directory(p.join(support.path, 'local')))),
      initialThemeModeProvider.overrideWithValue(themeMode),
      initialOnboardedProvider.overrideWithValue(onboarded),
    ],
  );
  await _startPlayer(container);
  runApp(UncontrolledProviderScope(container: container, child: const EarloomApp()));
}

/// Connects the player engine to the lock screen, notification, headset
/// and car controls. The engine runs whether or not this succeeds.
Future<void> _startPlayer(ProviderContainer container) async {
  final l10n = deviceL10n();
  final engine = container.read(playerEngineProvider);
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
      builder: () => AppAudioHandler(engine, onBookmark: bookmarkFromNotification, bookmarkLabel: l10n.playerBookmark),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.affluentlabs.earloom.playback',
        androidNotificationChannelName: l10n.playerNotificationChannel,
        androidNotificationIcon: 'drawable/ic_stat_earloom',
        fastForwardInterval: prefs.skipForward,
        rewindInterval: prefs.skipBack,
      ),
    );
  } on Object catch (e) {
    // Without the service, audio still plays while the app is open.
    debugPrint('Audio service did not start: $e');
  }
}
