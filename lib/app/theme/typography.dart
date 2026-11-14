// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

/// Bundled font families. Book titles are set in a serif display face, the
/// interface in a sans. Both ship as variable fonts in assets/fonts.
abstract final class AppFonts {
  static const sans = 'Inter';
  static const serif = 'Newsreader';
}

/// Builds the app [TextTheme]: `displaySmall`, `headlineMedium` and
/// `titleLarge` use the serif (they carry book titles), everything else the
/// sans.
TextTheme buildTextTheme(ColorScheme scheme) {
  final base = Typography.material2021(colorScheme: scheme);
  final sized = scheme.brightness == Brightness.dark ? base.white : base.black;
  final merged = base.englishLike.merge(sized);

  // Inter is already spaced for interfaces: the extra tracking Material adds
  // for its default font makes it look loose.
  TextStyle sans(TextStyle? s, {int weight = 400}) => _withFamily(s, AppFonts.sans, weight).copyWith(letterSpacing: 0);
  TextStyle serif(TextStyle? s, {int weight = 500}) =>
      _withFamily(s, AppFonts.serif, weight).copyWith(letterSpacing: -0.2, height: 1.15);

  return TextTheme(
    displayLarge: sans(merged.displayLarge),
    displayMedium: sans(merged.displayMedium),
    displaySmall: serif(merged.displaySmall),
    headlineLarge: sans(merged.headlineLarge, weight: 600),
    headlineMedium: serif(merged.headlineMedium),
    headlineSmall: sans(merged.headlineSmall, weight: 600),
    titleLarge: serif(merged.titleLarge, weight: 600),
    titleMedium: sans(merged.titleMedium, weight: 600),
    titleSmall: sans(merged.titleSmall, weight: 600),
    bodyLarge: sans(merged.bodyLarge),
    bodyMedium: sans(merged.bodyMedium),
    bodySmall: sans(merged.bodySmall),
    labelLarge: sans(merged.labelLarge, weight: 600),
    labelMedium: sans(merged.labelMedium, weight: 500),
    labelSmall: sans(merged.labelSmall, weight: 500),
  );
}

/// Section headings inside a screen ("Recently added", "This week"): the
/// sans, a step above list titles. Screen titles and book titles keep the
/// serif, so the serif always means "a name", never "a section".
extension SectionTitle on TextTheme {
  TextStyle? get sectionTitle => titleMedium?.copyWith(fontSize: 19, height: 1.2);
}

/// Variable fonts need the weight on the `wght` axis as well as in
/// [TextStyle.fontWeight], otherwise every weight renders as regular.
TextStyle _withFamily(TextStyle? style, String family, int weight) {
  return (style ?? const TextStyle()).copyWith(
    fontFamily: family,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation.weight(weight.toDouble())],
  );
}
