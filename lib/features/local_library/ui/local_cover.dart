// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';

/// The cover of a local book from its file, the way covers look everywhere
/// in the app: square, rounded, never stretched, with a quiet placeholder
/// when there is no picture.
class LocalCover extends StatelessWidget {
  const LocalCover({super.key, required this.file, required this.size, required this.title});

  /// Null when the book has no cover.
  final File? file;
  final double size;

  /// For the screen reader label.
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = _Placeholder(size: size);
    return Semantics(
      image: true,
      label: file == null ? l10n.bookNoCoverLabel : l10n.bookCoverLabel(title),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // Covers that are not square sit on a calm background.
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.cover * (size / 160).clamp(0.5, 1.0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: file == null
            ? placeholder
            : Image.file(
                file!,
                fit: BoxFit.contain,
                cacheWidth: cacheSize,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Icon(Icons.headphones_rounded, size: size * 0.36, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
    );
  }
}
