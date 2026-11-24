// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/providers.dart';
import '../../../../core/library/browse_models.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/book_groups.dart';
import 'browse_layout.dart';

/// "Show as one card in Audiobooks", on an author's or a series' screen:
/// its books then show together as one card instead of a card each.
class GroupSwitch extends ConsumerWidget {
  const GroupSwitch({super.key, required this.group});

  final BookGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: ref.watch(isGroupedProvider(group)),
      title: Text(l10n.groupSwitchTitle),
      subtitle: Text(l10n.groupSwitchBody),
      onChanged: (value) async {
        try {
          await setGrouped(ref.read(globalDbProvider), group, grouped: value);
        } on Object catch (e) {
          if (context.mounted) showActionError(context, e);
        }
      },
    );
  }
}
