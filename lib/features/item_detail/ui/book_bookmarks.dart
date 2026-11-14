// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/ui/book_actions.dart';
import '../../player/bookmarks.dart';
import '../../player/chapters.dart';
import '../../player/ui/player_widgets.dart';

/// The book's bookmarks on its page: tap one to play from there. Draws
/// nothing for a book without bookmarks, or while they load.
class BookBookmarks extends ConsumerWidget {
  const BookBookmarks({super.key, required this.itemRef, this.chapters = const []});

  final ItemRef itemRef;
  final List<Chapter> chapters;

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(bookmarksProvider(itemRef)).value;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.playerBookmarks, style: theme.textTheme.sectionTitle),
          const SizedBox(height: Space.xs),
          for (final b in list.take(_shown))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bookmark_rounded, color: scheme.primary),
              title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  formatClock(b.position),
                  if (chapters.isNotEmpty) chapters[chapterIndexAt(chapters, b.position)].title,
                ].join('  ·  '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              trailing: Icon(Icons.play_arrow_rounded, color: scheme.onSurfaceVariant),
              onTap: () => BookActions.play(ref, itemRef, startAt: b.position),
            ),
        ],
      ),
    );
  }
}
