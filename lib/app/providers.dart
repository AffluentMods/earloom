// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/account_db.dart';
import '../core/db/global_db.dart';
import 'theme/app_theme.dart';
import 'theme/cover_scheme.dart';

/// The app-wide database. Opened in `main` and provided through an override.
final globalDbProvider = Provider<GlobalDb>(
  (ref) => throw StateError('globalDbProvider must be overridden at startup'),
);

/// The cache database of the current account. Phase 1 provides it once an
/// account is active. Until then only debug screens override it.
final accountDbProvider = Provider<AccountDb>(
  (ref) => throw StateError('No active account'),
);

final coverSchemeServiceProvider = Provider<CoverSchemeService>(
  (ref) => CoverSchemeService(ref.watch(accountDbProvider)),
);

/// The theme mode read from disk before the first frame, so the app never
/// flashes the wrong theme. Overridden in `main`.
final initialThemeModeProvider = Provider<AppThemeMode>((ref) => AppThemeMode.system);

final themeModeProvider = NotifierProvider<ThemeModeController, AppThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => ref.read(initialThemeModeProvider);

  /// Applies the mode right away and saves it.
  Future<void> set(AppThemeMode mode) async {
    state = mode;
    await ref.read(globalDbProvider).writeSetting(SettingKeys.themeMode, mode.name);
  }
}
