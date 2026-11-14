// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/library/models.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// A small ring in a cover's corner: how far the user is, or a check mark
/// when the book is finished.
class ProgressBadge extends StatelessWidget {
  const ProgressBadge({super.key, required this.progress, this.size = 26});

  final ListeningProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final finished = progress.isFinished;
    return Semantics(
      label: finished ? l10n.genericFinished : l10n.listenedPercent((progress.fraction * 100).round()),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: finished ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: scheme.shadow.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 1)),
          ],
        ),
        child: finished
            ? Icon(Icons.check_rounded, size: size * 0.66, color: scheme.onPrimary)
            : Padding(
                padding: EdgeInsets.all(size * 0.16),
                child: CustomPaint(
                  painter: _RingPainter(
                    value: progress.fraction,
                    track: scheme.onSurface.withValues(alpha: 0.16),
                    color: scheme.primary,
                    stroke: math.max(2.5, size * 0.12),
                  ),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.track, required this.color, required this.stroke});

  final double value;
  final Color track;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inner, 0, math.pi * 2, false, paint..color = track);
    // A started book always shows a sliver, so "barely started" reads.
    final sweep = math.max(value, 0.04) * math.pi * 2;
    canvas.drawArc(inner, -math.pi / 2, sweep, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.color != color || old.stroke != stroke;
}

/// A thin rounded progress bar.
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({super.key, required this.value, this.height = 4, this.color, this.trackColor});

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color ?? scheme.primary,
        backgroundColor: trackColor ?? scheme.onSurface.withValues(alpha: 0.14),
      ),
    );
  }
}

/// A thin progress bar laid over the bottom of a cover.
class CoverProgressBar extends StatelessWidget {
  const CoverProgressBar({super.key, required this.progress});

  final ListeningProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.listenedPercent((progress.fraction * 100).round()),
      child: Container(
        height: 6,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.25), blurRadius: 4)],
        ),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          // A started book always shows a sliver, so "barely started" reads.
          widthFactor: progress.fraction.clamp(0.04, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(Radii.pill)),
          ),
        ),
      ),
    );
  }
}
