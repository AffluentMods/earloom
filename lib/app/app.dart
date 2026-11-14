// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/player/ui/player_side_effects.dart';
import '../l10n/gen/app_localizations.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class EarloomApp extends ConsumerWidget {
  const EarloomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      darkTheme: mode == AppThemeMode.amoled ? AppTheme.amoled() : AppTheme.dark(),
      themeMode: mode.materialMode,
      themeAnimationDuration: Motion.normal,
      routerConfig: ref.watch(routerProvider),
      // Above every route, so player snackbars show on any screen.
      builder: (context, child) => PlayerSideEffects(child: child ?? const SizedBox.shrink()),
    );
  }
}
