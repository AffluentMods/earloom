// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/account_db.dart';
import '../core/db/global_db.dart';
import '../features/accounts/data/account_session.dart';
import 'theme/app_theme.dart';
import 'theme/cover_scheme.dart';

/// The app-wide database. Opened in `main` and provided through an override.
final globalDbProvider = Provider<GlobalDb>(
  (ref) => throw StateError('globalDbProvider must be overridden at startup'),
);

/// The cache database of the current account. Throws when there is none:
/// screens that need it are only reachable with an account.
///
/// It is a scoped provider (`dependencies`), so a subtree (the developer
/// screens, tests) can be given its own database.
final accountDbProvider = Provider<AccountDb>((ref) {
  final session = ref.watch(accountSessionProvider);
  if (session == null) throw StateError('No active account');
  return session.db;
}, dependencies: [accountSessionProvider]);

final coverSchemeServiceProvider = Provider<CoverSchemeService>(
  (ref) => CoverSchemeService(ref.watch(accountDbProvider)),
  dependencies: [accountDbProvider],
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
