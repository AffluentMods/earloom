// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/app/theme/cover_scheme.dart';
import 'package:earloom/app/theme/cover_surfaces.dart';
import 'package:earloom/app/theme/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) => CoverSchemeService.contrastRatio(a, b);

/// Every text-on-background pairing the app is allowed to use.
Map<String, (Color, Color)> onRolePairs(ColorScheme s) => {
  'onSurface on surface': (s.onSurface, s.surface),
  'onSurface on surfaceContainerHighest': (s.onSurface, s.surfaceContainerHighest),
  'onSurfaceVariant on surface': (s.onSurfaceVariant, s.surface),
  'onSurfaceVariant on surfaceContainerHigh': (s.onSurfaceVariant, s.surfaceContainerHigh),
  'onPrimary on primary': (s.onPrimary, s.primary),
  'onPrimaryContainer on primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
  'onSecondary on secondary': (s.onSecondary, s.secondary),
  'onSecondaryContainer on secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
  'onTertiary on tertiary': (s.onTertiary, s.tertiary),
  'onTertiaryContainer on tertiaryContainer': (s.onTertiaryContainer, s.tertiaryContainer),
  'onError on error': (s.onError, s.error),
  'onErrorContainer on errorContainer': (s.onErrorContainer, s.errorContainer),
  'onInverseSurface on inverseSurface': (s.onInverseSurface, s.inverseSurface),
};

void expectAa(ColorScheme scheme, String label) {
  onRolePairs(scheme).forEach((name, pair) {
    expect(
      contrast(pair.$1, pair.$2),
      greaterThanOrEqualTo(4.5),
      reason: '$label: $name is below WCAG AA',
    );
  });
}

void main() {
  test('shell themes meet AA on every on-role', () {
    expectAa(AppTheme.shellScheme(Brightness.light), 'light');
    expectAa(AppTheme.shellScheme(Brightness.dark), 'dark');
    expectAa(AppTheme.shellScheme(Brightness.dark, amoled: true), 'amoled');
  });

  test('cover schemes meet AA on every on-role, across the whole color space', () {
    // Seeds across every hue at several saturations and lightnesses, plus
    // the awkward ones: near black, near white, gray, and the neutral seed.
    final seeds = <Color>[
      for (var hue = 0.0; hue < 360; hue += 15)
        for (final saturation in [0.25, 0.6, 1.0])
          for (final lightness in [0.2, 0.5, 0.8]) HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
      Colors.black,
      Colors.white,
      NeutralSeed.color,
      const HSLColor.fromAHSL(1, 0, 0, 0.5).toColor(),
    ];
    for (final seed in seeds) {
      for (final brightness in Brightness.values) {
        final label = 'seed ${seed.toARGB32().toRadixString(16)} ${brightness.name}';
        expectAa(CoverSchemeService.schemeFromSeed(seed, brightness), label);
      }
      expectAa(CoverSchemeService.schemeFromSeed(seed, Brightness.dark, amoled: true), 'seed amoled');
    }
  });

  test('text reads on the tinted cover backgrounds, for every cover color', () {
    final seeds = <Color>[
      for (var hue = 0.0; hue < 360; hue += 15)
        for (final saturation in [0.25, 0.6, 1.0])
          for (final lightness in [0.2, 0.5, 0.8]) HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
      Colors.black,
      Colors.white,
      NeutralSeed.color,
    ];
    for (final seed in seeds) {
      for (final (brightness, amoled) in [
        (Brightness.light, false),
        (Brightness.dark, false),
        (Brightness.dark, true),
      ]) {
        final scheme = CoverSchemeService.schemeFromSeed(seed, brightness, amoled: amoled);
        final label = 'seed ${seed.toARGB32().toRadixString(16)} ${brightness.name}${amoled ? ' amoled' : ''}';
        for (final background in [scheme.heroTint, ...scheme.ambientGradient]) {
          expect(contrast(scheme.onSurface, background), greaterThanOrEqualTo(7), reason: '$label onSurface');
          expect(contrast(scheme.onSurfaceVariant, background), greaterThanOrEqualTo(4.5), reason: '$label variant');
        }
        if (amoled) expect(scheme.ambientGradient.last, Colors.black, reason: label);
      }
    }
  });

  test('a pairing that already passes is left exactly as the scheme made it', () {
    final seed = const HSLColor.fromAHSL(1, 200, 0.6, 0.5).toColor();
    final raw = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    expect(CoverSchemeService.schemeFromSeed(seed, Brightness.dark).onSurface, raw.onSurface);
  });

  test('AMOLED turns the base surface pure black and keeps raised surfaces apart', () {
    final scheme = AppTheme.shellScheme(Brightness.dark, amoled: true);
    expect(scheme.surface, Colors.black);
    expect(scheme.surfaceContainerHigh, isNot(Colors.black));
  });
}
