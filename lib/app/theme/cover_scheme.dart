// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/account_db.dart';
import 'app_theme.dart';
import 'tokens.dart';

/// Turns a book cover into a [ColorScheme].
///
/// The seed color is cached per cover revision in `AccountDb.cover_colors`,
/// so the second open of a screen is instant and works offline. The same
/// seed always gives the same scheme, whether it came from the image or
/// from the cache.
class CoverSchemeService {
  CoverSchemeService(this._db);

  /// The current account's cache. Null with no server account (only books
  /// on this phone): seeds are then kept in memory for this run.
  final AccountDb? _db;
  final _memory = <String, int>{};

  /// Covers with less color than this are treated as gray and get the
  /// neutral shell seed: a tinted scheme from a gray cover looks muddy.
  static const minChroma = 8.0;

  /// Pass a small cover (`?width=128`), never the full-size image.
  Future<ColorScheme> schemeFor({
    required String itemId,
    required int coverUpdatedAt,
    required ImageProvider cover,
    required Brightness brightness,
    bool amoled = false,
  }) async {
    final memoryKey = '$itemId|$coverUpdatedAt';
    final cached = _memory[memoryKey] ?? (await _db?.coverColorsDao.lookup(itemId, coverUpdatedAt))?.seedArgb;
    if (cached != null) {
      _memory[memoryKey] = cached;
      return schemeFromSeed(Color(cached), brightness, amoled: amoled);
    }
    final seed = await extractSeed(cover);
    _memory[memoryKey] = seed.toARGB32();
    await _db?.coverColorsDao.put(itemId, coverUpdatedAt, seed.toARGB32());
    return schemeFromSeed(seed, brightness, amoled: amoled);
  }

  /// `fidelity` keeps the cover's own hue instead of a pastel version of it.
  ///
  /// Fidelity does not promise readable text on every pairing (a pale yellow
  /// cover in dark mode lands just under the bar), so every on-role is
  /// checked and nudged until it meets WCAG AA against its background.
  static ColorScheme schemeFromSeed(Color seed, Brightness brightness, {bool amoled = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: seed == NeutralSeed.color ? DynamicSchemeVariant.neutral : DynamicSchemeVariant.fidelity,
    );
    return ensureReadable(amoled && brightness == Brightness.dark ? AppTheme.toAmoled(scheme) : scheme);
  }

  /// WCAG AA for normal text.
  static const minContrast = 4.5;

  /// For text on tinted containers (the mini player, Resume buttons, chips).
  /// Material puts it right at 4.5:1, which reads washed out on a colored
  /// fill; 7:1 keeps the fill and makes the text crisp.
  static const containerContrast = 7.0;

  /// Returns [scheme] with every on-role readable on its background.
  static ColorScheme ensureReadable(ColorScheme scheme) {
    Color on(Color foreground, List<Color> backgrounds, {double target = minContrast}) {
      var result = foreground;
      for (final background in backgrounds) {
        result = _readableOn(result, background, target);
      }
      return result;
    }

    const crisp = containerContrast;
    return scheme.copyWith(
      onSurface: on(scheme.onSurface, [scheme.surface, scheme.surfaceContainerHighest]),
      onSurfaceVariant: on(scheme.onSurfaceVariant, [scheme.surface, scheme.surfaceContainerHigh]),
      onPrimary: on(scheme.onPrimary, [scheme.primary]),
      onPrimaryContainer: on(scheme.onPrimaryContainer, [scheme.primaryContainer], target: crisp),
      onSecondary: on(scheme.onSecondary, [scheme.secondary]),
      onSecondaryContainer: on(scheme.onSecondaryContainer, [scheme.secondaryContainer], target: crisp),
      onTertiary: on(scheme.onTertiary, [scheme.tertiary]),
      onTertiaryContainer: on(scheme.onTertiaryContainer, [scheme.tertiaryContainer], target: crisp),
      onError: on(scheme.onError, [scheme.error]),
      onErrorContainer: on(scheme.onErrorContainer, [scheme.errorContainer], target: crisp),
      onInverseSurface: on(scheme.onInverseSurface, [scheme.inverseSurface]),
    );
  }

  /// WCAG contrast ratio between two opaque colors, from 1 to 21.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  /// Moves [foreground] lighter or darker, keeping its hue, until it reaches
  /// [target] on [background]. Colors that already pass come back unchanged.
  static Color _readableOn(Color foreground, Color background, double target) {
    if (contrastRatio(foreground, background) >= target) return foreground;
    final hct = Hct.fromInt(foreground.toARGB32());
    final lighten = hct.tone >= Hct.fromInt(background.toARGB32()).tone;
    var candidate = foreground;
    for (var tone = hct.tone; tone >= 0 && tone <= 100; tone += lighten ? 1 : -1) {
      candidate = Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
      if (contrastRatio(candidate, background) >= target) return candidate;
    }
    // Ran out of room in that direction: black or white always has the most.
    return contrastRatio(Colors.white, background) >= contrastRatio(Colors.black, background)
        ? Colors.white
        : Colors.black;
  }

  /// Finds the color that best represents the image, or [NeutralSeed.color]
  /// for a gray image.
  static Future<Color> extractSeed(ImageProvider cover) async {
    final image = await _load(ResizeImage.resizeIfNeeded(_sampleSize, _sampleSize, cover));
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return NeutralSeed.color;
      final pixels = <int>[];
      for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
        final a = bytes.getUint8(i + 3);
        if (a < 255) continue; // Skip transparent pixels.
        pixels.add(0xFF000000 | bytes.getUint8(i) << 16 | bytes.getUint8(i + 1) << 8 | bytes.getUint8(i + 2));
      }
      if (pixels.isEmpty) return NeutralSeed.color;
      final quantized = await QuantizerCelebi().quantize(pixels, 128);
      // Score.score falls back to a fixed blue when nothing is colorful
      // enough. Passing our neutral seed as the fallback makes gray covers
      // land on the shell color instead.
      final ranked = Score.score(quantized.colorToCount, desired: 1, fallbackColorARGB: NeutralSeed.color.toARGB32());
      final seed = ranked.first;
      if (Hct.fromInt(seed).chroma < minChroma) return NeutralSeed.color;
      return Color(seed);
    } finally {
      image.dispose();
    }
  }

  static const _sampleSize = 96;

  static Future<ui.Image> _load(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        // Clone: the stream may dispose its own handle once we stop listening.
        completer.complete(info.image.clone());
        info.dispose();
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
