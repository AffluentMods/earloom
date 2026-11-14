// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/library_providers.dart';
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';
import 'widgets/collection_scaffold.dart';

/// The books of one library that match one filter. This is the Narrator
/// screen (there is no narrator entity on the server), and where genre and
/// tag chips lead.
class FilteredBooksScreen extends ConsumerWidget {
  const FilteredBooksScreen({super.key, required this.source, required this.libraryId, required this.filter});

  final SourceId source;
  final String libraryId;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = LibraryQuery(filters: [filter]);
    final books = ref.watch(libraryBooksProvider((source: source, libraryId: libraryId, query: query, limit: 2000)));
    final list = books.value ?? const [];
    final kicker = switch (filter.kind) {
      FilterKind.narrator => l10n.narratorLabel,
      FilterKind.genre => l10n.searchGenre,
      FilterKind.tag => l10n.searchTag,
      FilterKind.author => l10n.librarySortAuthor,
      FilterKind.language => l10n.itemLanguage,
      _ => null,
    };
    return CollectionScaffold(
      title: filter.label,
      kicker: kicker,
      subtitle: list.isEmpty ? null : l10n.bookCountLabel(list.length),
      themeBook: list.isEmpty ? null : list.first,
      artwork: CoverStack(books: list, size: 180),
      slivers: [
        if (books.isLoading && list.isEmpty) const SliverToBoxAdapter(child: ShelfSkeleton()),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => BookListRow(book: list[i], place: 'filtered'),
        ),
        if (!books.isLoading && list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(l10n.libraryEmptyFiltered, textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}
