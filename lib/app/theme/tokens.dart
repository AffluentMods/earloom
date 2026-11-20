// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

/// Spacing scale, in logical pixels.
abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;
}

/// Corner radii.
abstract final class Radii {
  static const cover = 14.0, card = 20.0, sheet = 28.0, pill = 999.0;
}

/// Animation durations.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 500);
}

/// Neutral seed for the app shell. The only raw color literal allowed in lib/.
/// Everything else comes from a [ColorScheme]: the shell scheme built from
/// this seed, or the scheme of the current cover.
abstract final class NeutralSeed {
  static const color = Color(0xFF6B6F80);
}

/// The light theme's paper: every light surface is a tone of this one
/// near-gray, a faint cool slate, whatever the cover. Material's own light
/// neutrals lean toward the seed's hue, which reads pink or beige on white;
/// in light mode the covers bring the color, the surfaces stay clean.
abstract final class Paper {
  /// HCT hue and chroma.
  static const hue = 230.0, chroma = 4.0;

  /// The shell's own accent (selected tabs, toggles, neutral buttons):
  /// the same slate with more color in it.
  static const accentChroma = 14.0;
}

/// Window width breakpoints for tablet layouts (`WindowSize` in
/// core/ui/adaptive.dart turns a width into a size class).
abstract final class Breakpoints {
  static const medium = 600.0, expanded = 840.0, large = 1200.0;
}
