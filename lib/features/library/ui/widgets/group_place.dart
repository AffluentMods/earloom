// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/library/browse_models.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/book_groups.dart';
import 'browse_layout.dart';

/// The choices of [GroupPlaceTile], in the order the sheet lists them.
enum GroupPlaceChoice {
  each(null),
  audiobooks(BookGroupPlace.audiobooks),
  podcasts(BookGroupPlace.podcasts);

  const GroupPlaceChoice(this.place);

  /// Null for a card each in Audiobooks.
  final BookGroupPlace? place;

  static GroupPlaceChoice of(BookGroupPlace? place) => values.firstWhere((c) => c.place == place);

  String label(AppLocalizations l10n) => switch (this) {
    each => l10n.groupPlaceEach,
    audiobooks => l10n.groupPlaceAudiobooks,
    podcasts => l10n.groupPlacePodcasts,
  };
}

/// "Where its books show", on an author's or a series' screen: a card
/// each in Audiobooks, one card in Audiobooks, or one card in Podcasts.
class GroupPlaceTile extends ConsumerWidget {
  const GroupPlaceTile({super.key, required this.group});

  final BookGroup group;

  Future<void> _pick(BuildContext context, WidgetRef ref, GroupPlaceChoice current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<GroupPlaceChoice>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
              child: Text(l10n.groupPlaceTitle, style: Theme.of(sheet).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text(
                l10n.groupPlaceBody,
                style: Theme.of(sheet).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(sheet).colorScheme.onSurfaceVariant),
              ),
            ),
            RadioGroup<GroupPlaceChoice>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(sheet, v),
              child: Column(
                children: [
                  for (final c in GroupPlaceChoice.values)
                    RadioListTile<GroupPlaceChoice>(value: c, title: Text(c.label(l10n))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await setGroupPlace(ref.read(globalDbProvider), group, picked.place);
    } on Object catch (e) {
      if (context.mounted) showActionError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = GroupPlaceChoice.of(ref.watch(groupPlaceProvider(group)));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.groupPlaceTitle),
      subtitle: Text(current.label(l10n)),
      trailing: const Icon(Icons.unfold_more_rounded),
      onTap: () => _pick(context, ref, current),
    );
  }
}
