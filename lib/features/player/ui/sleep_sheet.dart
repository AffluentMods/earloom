// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import '../sleep_timer.dart';
import 'player_widgets.dart';

Future<void> showSleepSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const SleepSheet(),
);

class SleepSheet extends ConsumerWidget {
  const SleepSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (sleep, left, chapterIndex) = ref.watch(
      playerProvider.select((s) => (s.sleep, s.sleepRemaining, s.chapterIndex)),
    );
    final engine = ref.read(playerEngineProvider);
    final last = ref.watch(playerPrefsProvider.select((p) => p.sleepLast));

    void start(SleepTimer timer) {
      HapticFeedback.selectionClick();
      engine.setSleepTimer(timer);
      Navigator.of(context).pop();
    }

    void minutes(int m) => start(
      SleepAfter(
        original: Duration(minutes: m),
        remaining: Duration(minutes: m),
      ),
    );

    final status = switch (sleep) {
      SleepOff() => null,
      SleepAfter() => l10n.sleepActive(left == null ? '' : formatClock(left)),
      SleepAtChapterEnd() => l10n.sleepActiveChapter,
      SleepAtBookEnd() => l10n.sleepActiveBook,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.playerSleepTimer, style: theme.textTheme.titleLarge),
          if (status != null) ...[
            const SizedBox(height: Space.md),
            Card.filled(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bedtime_rounded, color: scheme.onSecondaryContainer),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            status,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Wrap(
                      spacing: Space.sm,
                      children: [
                        FilledButton.tonal(
                          onPressed: engine.extendSleepTimer,
                          child: Text(
                            l10n.sleepAddTime(sleep is SleepAfter ? sleep.original.inMinutes : last.inMinutes),
                          ),
                        ),
                        TextButton(
                          onPressed: () => start(const SleepOff()),
                          child: Text(l10n.sleepOff),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in sleepPresetMinutes)
                ChoiceChip(
                  label: Text(l10n.sleepMinutes(m)),
                  selected: sleep is SleepAfter && sleep.original.inMinutes == m,
                  onSelected: (_) => minutes(m),
                ),
              ActionChip(
                avatar: const Icon(Icons.tune_rounded),
                label: Text(l10n.sleepCustom),
                onPressed: () async {
                  final value = await _askMinutes(context, last.inMinutes);
                  if (value != null) minutes(value);
                },
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmark_border_rounded),
            title: Text(l10n.sleepEndOfChapter),
            selected: sleep is SleepAtChapterEnd,
            onTap: () => start(SleepAtChapterEnd(chapterIndex)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_rounded),
            title: Text(l10n.sleepEndOfBook),
            selected: sleep is SleepAtBookEnd,
            onTap: () => start(const SleepAtBookEnd()),
          ),
          const SizedBox(height: Space.sm),
          Text(l10n.sleepShakeHint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<int?> _askMinutes(BuildContext context, int initial) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '$initial');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sleepCustomTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
          decoration: InputDecoration(labelText: l10n.sleepCustomField),
          onSubmitted: (v) => Navigator.of(context).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.genericCancel)),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              Navigator.of(context).pop(v == null || v <= 0 ? null : v);
            },
            child: Text(l10n.sleepStart),
          ),
        ],
      ),
    );
  }
}
