// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../player/ui/player_widgets.dart';
import '../data/book_listening.dart';

/// The "Your listening" block on a book page. Draws nothing for a book
/// never played, or while the numbers load.
class BookListeningCard extends ConsumerWidget {
  const BookListeningCard({super.key, required this.itemRef});
  final ItemRef itemRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(bookListeningProvider(itemRef)).value;
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale);
    final speed = data.averageSpeed;
    final rows = [
      (Icons.schedule_rounded, l10n.itemTimeSpent(formatDurationShort(l10n, data.time))),
      (Icons.repeat_rounded, l10n.itemSessions(data.sessions)),
      if (data.startedOn != null) (Icons.play_circle_outline_rounded, l10n.itemStartedOn(date.format(data.startedOn!))),
      if (data.finishedOn != null)
        (Icons.check_circle_outline_rounded, l10n.itemFinishedOn(date.format(data.finishedOn!))),
      if (speed != null && (speed - 1).abs() > 0.02) (Icons.speed_rounded, l10n.itemAvgSpeed(formatSpeed(l10n, speed))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.itemYourListening, style: theme.textTheme.sectionTitle),
        const SizedBox(height: Space.sm),
        for (final (icon, text) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: Space.md),
                Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
