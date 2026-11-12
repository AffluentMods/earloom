// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// A cover the way the app shows them everywhere: never stretched, rounded,
/// with a soft shadow.
class PreviewCover extends StatelessWidget {
  const PreviewCover({super.key, required this.image, required this.size});

  final ImageProvider image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Covers that are not square sit on a palette background.
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.cover),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.35),
            blurRadius: size * 0.14,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(image: image, fit: BoxFit.contain),
    );
  }
}

/// Skip back or forward button that shows its interval, like "15" or "30".
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.seconds, required this.forward});

  final int seconds;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: () {},
      tooltip: forward ? 'Forward $seconds seconds' : 'Back $seconds seconds',
      iconSize: 44,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(flipX: forward, child: const Icon(Icons.replay_rounded)),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '$seconds',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation.weight(700)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
