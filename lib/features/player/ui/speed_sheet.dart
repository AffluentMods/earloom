// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import '../player_prefs.dart';
import 'player_widgets.dart';

Future<void> showSpeedSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const SpeedSheet(),
);

/// Speed from 0.5x to 3.5x: a big readout, fine steps, presets.
class SpeedSheet extends ConsumerWidget {
  const SpeedSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final speed = ref.watch(playerProvider.select((s) => s.speed));
    final perBook = ref.watch(playerPrefsProvider.select((p) => p.speedPerBook));
    final engine = ref.read(playerEngineProvider);
    void set(double value) {
      if ((value - speed).abs() < 0.001) return;
      HapticFeedback.selectionClick();
      engine.setSpeed(value);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.playerSpeed, style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: speed <= PlayerPrefs.minSpeed ? null : () => set(speed - 0.05),
                tooltip: l10n.speedSlower,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text(
                  formatSpeed(l10n, speed),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: speed >= PlayerPrefs.maxSpeed ? null : () => set(speed + 0.05),
                tooltip: l10n.speedFaster,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Slider(
            value: speed.clamp(PlayerPrefs.minSpeed, PlayerPrefs.maxSpeed),
            min: PlayerPrefs.minSpeed,
            max: PlayerPrefs.maxSpeed,
            divisions: ((PlayerPrefs.maxSpeed - PlayerPrefs.minSpeed) / 0.05).round(),
            label: formatSpeed(l10n, speed),
            semanticFormatterCallback: (v) => formatSpeed(l10n, v),
            onChanged: set,
          ),
          const SizedBox(height: Space.sm),
          Text(l10n.speedPresets, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final preset in PlayerPrefs.speedPresets)
                ChoiceChip(
                  label: Text(formatSpeed(l10n, preset)),
                  selected: (preset - speed).abs() < 0.001,
                  onSelected: (_) => set(preset),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.speedRememberPerBook),
            value: perBook,
            onChanged: (v) => ref.read(playerPrefsProvider.notifier).update((p) => p.copyWith(speedPerBook: v)),
          ),
        ],
      ),
    );
  }
}
