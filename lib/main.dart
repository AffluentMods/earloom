// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/theme/app_theme.dart';
import 'core/db/global_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final globalDb = GlobalDb.open();
  final themeMode = AppThemeMode.fromName(await globalDb.readSetting(SettingKeys.themeMode));
  runApp(
    ProviderScope(
      overrides: [
        globalDbProvider.overrideWithValue(globalDb),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const EarloomApp(),
    ),
  );
}
