// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('light, dark and AMOLED switch at runtime and are saved', (tester) async {
    final db = await pumpEarloom(tester, themeMode: AppThemeMode.light);
    ThemeData theme() => Theme.of(tester.element(find.byType(HomeScreen)));
    final controller = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .read(themeModeProvider.notifier);

    expect(theme().brightness, Brightness.light);

    await tester.runAsync(() => controller.set(AppThemeMode.dark));
    await tester.pumpAndSettle();
    expect(theme().brightness, Brightness.dark);
    expect(theme().colorScheme.surface, isNot(Colors.black));

    await tester.runAsync(() => controller.set(AppThemeMode.amoled));
    await tester.pumpAndSettle();
    expect(theme().brightness, Brightness.dark);
    expect(theme().colorScheme.surface, Colors.black);
    expect(await tester.runAsync(() => db.readSetting(SettingKeys.themeMode)), 'amoled');

    await tester.runAsync(() => controller.set(AppThemeMode.light));
    await tester.pumpAndSettle();
    expect(theme().brightness, Brightness.light);
  });

  testWidgets('book titles use the serif, the interface the sans', (tester) async {
    await pumpEarloom(tester);
    final text = Theme.of(tester.element(find.byType(HomeScreen))).textTheme;
    for (final style in [text.displaySmall, text.headlineMedium, text.titleLarge]) {
      expect(style?.fontFamily, 'Newsreader');
    }
    for (final style in [text.bodyLarge, text.bodyMedium, text.labelLarge, text.titleMedium, text.titleSmall]) {
      expect(style?.fontFamily, 'Inter');
    }
  });

  test('an unknown saved value falls back to system', () {
    expect(AppThemeMode.fromName(null), AppThemeMode.system);
    expect(AppThemeMode.fromName('sepia'), AppThemeMode.system);
    expect(AppThemeMode.fromName('amoled'), AppThemeMode.amoled);
  });
}
