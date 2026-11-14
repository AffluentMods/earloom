// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/download_rules.dart';
import '../data/offline_providers.dart';
import 'sync_status.dart';

/// Settings > Downloads (docs/plan/05-phase4-offline.md 4.5). Reached from
/// the Downloads screen; Phase 8 links it from Settings too.
class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(downloadSettingsProvider);
    final controller = ref.read(downloadSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    void set(DownloadSettings Function(DownloadSettings) change) {
      unawaited(HapticFeedback.selectionClick());
      unawaited(controller.update(change));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDownloadsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          _Header(label: l10n.settingsDownloadsNetwork),
          SwitchListTile(
            title: Text(l10n.settingsDownloadsWifiOnly),
            subtitle: Text(l10n.settingsDownloadsWifiOnlyBody),
            value: settings.wifiOnly,
            onChanged: (v) => set((s) => s.copyWith(wifiOnly: v)),
          ),
          _Header(label: l10n.settingsDownloadsRules),
          SwitchListTile(
            title: Text(l10n.settingsDownloadsAutoNextInSeries),
            subtitle: Text(l10n.settingsDownloadsAutoNextBody),
            value: settings.autoNextInSeries,
            onChanged: (v) => set((s) => s.copyWith(autoNextInSeries: v)),
          ),
          SwitchListTile(
            title: Text(l10n.settingsDownloadsAutoDelete(autoDeleteAfter.inDays)),
            subtitle: Text(l10n.settingsDownloadsAutoDeleteBody),
            value: settings.autoDeleteFinished,
            onChanged: (v) => set((s) => s.copyWith(autoDeleteFinished: v)),
          ),
          ListTile(
            title: Text(l10n.settingsDownloadsMaxSizeTitle),
            subtitle: Text(l10n.settingsDownloadsMaxSizeBody),
            trailing: DropdownButton<int>(
              value: DownloadSettings.maxGbChoices.contains(settings.maxGigabytes) ? settings.maxGigabytes : 0,
              underline: const SizedBox.shrink(),
              onChanged: (v) => set((s) => s.copyWith(maxGigabytes: v ?? 0)),
              items: [
                for (final gb in DownloadSettings.maxGbChoices)
                  DropdownMenuItem(
                    value: gb,
                    child: Text(gb == 0 ? l10n.settingsDownloadsMaxSizeOff : l10n.settingsDownloadsMaxSize(gb)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    l10n.settingsDownloadsNeverUnfinished,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SyncStatusTile(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
