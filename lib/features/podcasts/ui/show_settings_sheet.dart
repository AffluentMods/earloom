// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../player/player_controller.dart';
import '../../player/player_prefs.dart';
import '../../player/ui/player_widgets.dart' show formatSpeed;
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';

/// This phone's settings for one show (docs/plan/06-phase5-podcasts.md
/// 5.4): automatic downloads, how many to keep, removing played episodes,
/// new episode notifications and the show's speed.
Future<void> showShowSettings(BuildContext context, ItemRef show, {required String title}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ShowSettingsSheet(show: show, title: title, controller: scroll),
      ),
    );

class ShowSettingsSheet extends ConsumerWidget {
  const ShowSettingsSheet({super.key, required this.show, required this.title, this.controller});

  final ItemRef show;
  final String title;
  final ScrollController? controller;

  Future<void> _save(WidgetRef ref, ShowPrefs prefs, {bool speedChanged = false}) async {
    final repository = ref.read(podcastRepositoryProvider);
    if (repository == null) return;
    await repository.savePrefs(show.itemId, prefs);
    final now = ref.read(playerProvider).now?.ref;
    if (speedChanged && now?.episodeId != null && now?.itemId == show.itemId) {
      await ref.read(playerEngineProvider).reapplySpeed();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prefs = ref.watch(showPrefsProvider(show)).value ?? const ShowPrefs();
    final podcastDefault = ref.watch(playerPrefsProvider.select((p) => p.podcastSpeed));
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
    );
    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Text(l10n.podcastSettingsTitle, style: theme.textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, 0),
          child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        heading(l10n.podcastSettingsDownloads),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.podcastAutoDownload),
          subtitle: Text(l10n.podcastAutoDownloadBody),
          value: prefs.autoDownload,
          onChanged: (v) => _save(ref, prefs.copyWith(autoDownload: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.podcastKeepLatestTitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: prefs.autoDownload ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final n in ShowPrefs.keepChoices)
                    ChoiceChip(
                      label: Text(n == 0 ? l10n.podcastKeepAll : l10n.podcastKeepLatest(n)),
                      selected: prefs.keepLatest == n,
                      onSelected: prefs.autoDownload ? (_) => _save(ref, prefs.copyWith(keepLatest: n)) : null,
                    ),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.podcastDeletePlayed),
          subtitle: Text(l10n.podcastDeletePlayedBody),
          value: prefs.deletePlayed,
          onChanged: prefs.autoDownload ? (v) => _save(ref, prefs.copyWith(deletePlayed: v)) : null,
        ),
        heading(l10n.podcastSettingsNotifications),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.podcastNotifyNew),
          subtitle: Text(l10n.podcastNotifyNewBody),
          value: prefs.notifyNew,
          onChanged: (v) async {
            if (v) {
              final allowed = await ref.read(episodeNotifierProvider).requestPermission();
              if (!allowed) {
                if (context.mounted) showMessage(context, l10n.podcastNotifyDenied);
                return;
              }
            }
            await _save(ref, prefs.copyWith(notifyNew: v));
          },
        ),
        heading(l10n.podcastShowSpeed),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
          child: Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              ChoiceChip(
                label: Text(l10n.podcastSpeedDefault(formatSpeed(l10n, podcastDefault))),
                selected: prefs.speed == null,
                onSelected: (_) => unawaited(_save(ref, prefs.copyWith(clearSpeed: true), speedChanged: true)),
              ),
              for (final s in {...PlayerPrefs.speedPresets, ?prefs.speed}.toList()..sort())
                ChoiceChip(
                  label: Text(formatSpeed(l10n, s)),
                  selected: prefs.speed != null && (prefs.speed! - s).abs() < 0.001,
                  onSelected: (_) => unawaited(_save(ref, prefs.copyWith(speed: s), speedChanged: true)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
