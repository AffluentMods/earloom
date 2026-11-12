// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/app/theme/cover_scheme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // CoverTheme animates from the theme the app is showing (as Theme.of gives
  // it back, already localized by MaterialApp) to a theme built from the
  // cover. Every text style on both sides must agree on `inherit`, or the
  // animation throws on its first frame.
  for (final (name, shell) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('amoled', AppTheme.amoled),
  ]) {
    testWidgets('the $name theme animates to a cover theme and back', (tester) async {
      late ThemeData shown;
      await tester.pumpWidget(
        MaterialApp(
          theme: shell(),
          home: Builder(
            builder: (context) {
              shown = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final cover = AppTheme.fromScheme(
        CoverSchemeService.schemeFromSeed(const Color(0xFF0B3954), shown.brightness),
      );
      expect(() => ThemeData.lerp(shown, cover, 0.5), returnsNormally);
      expect(() => ThemeData.lerp(cover, shown, 0.5), returnsNormally);
    });
  }
}
