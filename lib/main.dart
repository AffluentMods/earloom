// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final globalDb = GlobalDb.open();
  final localDb = LocalDb.open();
  final support = await getApplicationSupportDirectory();
  final themeMode = AppThemeMode.fromName(await globalDb.readSetting(SettingKeys.themeMode));
  runApp(
    ProviderScope(
      overrides: [
        globalDbProvider.overrideWithValue(globalDb),
        localDbProvider.overrideWithValue(localDb),
        localStorageProvider.overrideWithValue(LocalStorage(Directory(p.join(support.path, 'local')))),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const EarloomApp(),
    ),
  );
}
