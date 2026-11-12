// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';
import 'typography.dart';

/// The theme choices offered to the user. Stored in GlobalDb settings.
enum AppThemeMode {
  system,
  light,
  dark,

  /// Dark with pure black surfaces, for OLED screens.
  amoled;

  static AppThemeMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => AppThemeMode.system);

  ThemeMode get materialMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark || AppThemeMode.amoled => ThemeMode.dark,
  };
}

abstract final class AppTheme {
  /// Neutral shell scheme. Color in the app comes from covers, not from here.
  static ColorScheme shellScheme(Brightness brightness, {bool amoled = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: NeutralSeed.color,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    return amoled ? toAmoled(scheme) : scheme;
  }

  /// Forces the base surfaces of a dark scheme to pure black and keeps the
  /// raised container roles close to it, so cards still separate from the
  /// background.
  static ColorScheme toAmoled(ColorScheme scheme) {
    assert(scheme.brightness == Brightness.dark, 'AMOLED only applies to dark schemes');
    const black = Colors.black;
    Color lift(double amount) => Color.lerp(black, scheme.surfaceContainerHighest, amount)!;
    return scheme.copyWith(
      surface: black,
      surfaceDim: black,
      surfaceContainerLowest: black,
      surfaceContainerLow: lift(0.25),
      surfaceContainer: lift(0.4),
      surfaceContainerHigh: lift(0.6),
      surfaceContainerHighest: lift(0.8),
    );
  }

  static ThemeData light() => fromScheme(shellScheme(Brightness.light));
  static ThemeData dark() => fromScheme(shellScheme(Brightness.dark));
  static ThemeData amoled() => fromScheme(shellScheme(Brightness.dark, amoled: true));

  /// Builds the full theme from any scheme: the neutral shell scheme, or the
  /// scheme of a cover for the screens that take their color from the book.
  static ThemeData fromScheme(ColorScheme scheme) {
    final text = buildTextTheme(scheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.card))),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
        thumbColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }
}
