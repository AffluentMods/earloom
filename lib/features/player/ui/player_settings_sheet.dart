// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import '../player_prefs.dart';

Future<void> showPlayerSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, scroll) => PlayerSettingsList(controller: scroll),
  ),
);

/// The listening comfort settings. Also used on the Settings screen.
class PlayerSettingsList extends ConsumerWidget {
  const PlayerSettingsList({super.key, this.controller, this.showTitle = true});
  final ScrollController? controller;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prefs = ref.watch(playerPrefsProvider);
    final notifier = ref.read(playerPrefsProvider.notifier);
    void set(PlayerPrefs Function(PlayerPrefs) change) => notifier.update(change);
    final android = Platform.isAndroid;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
    );

    Widget skipChooser(String label, Duration value, PlayerPrefs Function(Duration) apply) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final seconds in PlayerPrefs.skipChoices)
                ChoiceChip(
                  label: Text(l10n.playerSettingsSeconds(seconds)),
                  selected: value.inSeconds == seconds,
                  onSelected: (_) => set((_) => apply(Duration(seconds: seconds))),
                ),
            ],
          ),
        ],
      ),
    );

    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: Text(l10n.playerSettings, style: theme.textTheme.titleLarge),
          ),
        skipChooser(l10n.playerSettingsSkipBack, prefs.skipBack, (d) => prefs.copyWith(skipBack: d)),
        skipChooser(l10n.playerSettingsSkipForward, prefs.skipForward, (d) => prefs.copyWith(skipForward: d)),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.playerSettingsSmartRewind),
          subtitle: Text(l10n.playerSettingsSmartRewindHint),
          value: prefs.smartRewind,
          onChanged: (v) => set((p) => p.copyWith(smartRewind: v)),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.speedRememberPerBook),
          value: prefs.speedPerBook,
          onChanged: (v) => set((p) => p.copyWith(speedPerBook: v)),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.playerSettingsAutoPlay),
          value: prefs.autoPlay == AutoPlay.queueThenStop,
          onChanged: (v) => set((p) => p.copyWith(autoPlay: v ? AutoPlay.queueThenStop : AutoPlay.stop)),
        ),
        if (android) ...[
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            title: Text(l10n.playerSettingsSkipSilence),
            value: prefs.skipSilence,
            onChanged: (v) => set((p) => p.copyWith(skipSilence: v)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            title: Text(l10n.playerSettingsBoost),
            trailing: Text(
              prefs.boostDecibels == 0
                  ? l10n.playerSettingsBoostOff
                  : l10n.playerSettingsBoostValue(prefs.boostDecibels.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Slider(
              value: prefs.boostDecibels,
              max: 10,
              divisions: 10,
              label: l10n.playerSettingsBoostValue(prefs.boostDecibels.round()),
              onChanged: (v) => set((p) => p.copyWith(boostDecibels: v)),
            ),
          ),
        ],
        heading(l10n.playerSettingsRemoteButtons),
        RadioGroup<RemoteButtons>(
          groupValue: prefs.remoteButtons,
          onChanged: (v) => set((p) => p.copyWith(remoteButtons: v)),
          child: Column(
            children: [
              RadioListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                value: RemoteButtons.skip,
                title: Text(l10n.playerSettingsRemoteSkip),
              ),
              RadioListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                value: RemoteButtons.chapters,
                title: Text(l10n.playerSettingsRemoteChapters),
              ),
            ],
          ),
        ),
        heading(l10n.playerSleepTimer),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.sleepFadeOut(prefs.sleepFade.inSeconds)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Slider(
            value: prefs.sleepFade.inSeconds.toDouble().clamp(0, 60),
            max: 60,
            divisions: 12,
            label: l10n.playerSettingsSeconds(prefs.sleepFade.inSeconds),
            onChanged: (v) => set((p) => p.copyWith(sleepFade: Duration(seconds: v.round()))),
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.sleepShakeToExtend),
          subtitle: Text(l10n.sleepShakeHint),
          value: prefs.shakeToExtend,
          onChanged: (v) => set((p) => p.copyWith(shakeToExtend: v)),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          title: Text(l10n.playerSettingsScrubber),
          value: prefs.chapterScrubber,
          onChanged: (v) => set((p) => p.copyWith(chapterScrubber: v)),
        ),
      ],
    );
  }
}
