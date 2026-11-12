// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import 'cover_scheme.dart';

/// Tinted backgrounds for the screens that take their color from a cover.
///
/// The on-roles of a scheme only promise contrast against their own
/// background role. A gradient mixes roles, so every color here is pulled
/// toward the surface until `onSurface` and `onSurfaceVariant` both read
/// on it. Text over these backgrounds uses those two roles and nothing else.
extension CoverSurfaces on ColorScheme {
  /// Top color of the Item Detail gradient, which fades down to [surface].
  Color get heroTint => _readableTint(primaryContainer);

  /// The three colors of the Now Playing background.
  ///
  /// The third stop only leans toward the tertiary color: on its own the
  /// tertiary is close to the cover's opposite hue and turns the gradient
  /// muddy. On AMOLED the gradient is kept faint and ends in pure black.
  List<Color> get ambientGradient {
    final amoled = surface == Colors.black;
    final strength = amoled ? 0.45 : 0.8;
    Color soft(Color c) => _readableTint(Color.lerp(surface, c, strength)!);
    return [
      soft(primaryContainer),
      soft(secondaryContainer),
      amoled ? surface : soft(Color.lerp(secondaryContainer, tertiaryContainer, 0.3)!),
    ];
  }

  /// [tint], mixed with the surface just enough for body text to read on it.
  Color _readableTint(Color tint) {
    for (var amount = 1.0; amount > 0; amount -= 0.05) {
      final color = Color.lerp(surface, tint, amount)!;
      if (CoverSchemeService.contrastRatio(onSurface, color) >= _comfortable &&
          CoverSchemeService.contrastRatio(onSurfaceVariant, color) >= CoverSchemeService.minContrast) {
        return color;
      }
    }
    return surface;
  }

  /// Titles sit on these tints, so aim well above the AA minimum.
  static const _comfortable = 7.0;
}
