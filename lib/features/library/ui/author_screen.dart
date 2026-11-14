// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/html_text.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/library_providers.dart';
import 'browse_nav.dart';
import 'widgets/book_cards.dart';
import 'widgets/book_cover.dart';
import 'widgets/browse_layout.dart';
import 'widgets/collection_scaffold.dart';

/// An author: photo, biography, books grouped by series (in sequence), then
/// the rest.
class AuthorScreen extends ConsumerStatefulWidget {
  const AuthorScreen({super.key, required this.source, required this.authorId});

  final SourceId source;

  /// The server id, or the name for On this device.
  final String authorId;

  @override
  ConsumerState<AuthorScreen> createState() => _AuthorScreenState();
}

class _AuthorScreenState extends ConsumerState<AuthorScreen> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null || repository.source != widget.source) return;
    await runRefresh(() => repository.refreshAuthor(widget.authorId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final author = ref.watch(authorProvider((source: widget.source, id: widget.authorId)));
    final value = author.value;
    if (value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: author.isLoading
            ? const Center(child: ShelfSkeleton())
            : EmptyState(icon: Icons.person_outline_rounded, title: l10n.authorNotFound),
      );
    }
    final libraryId = widget.source is LocalSource ? localLibraryId : _libraryOf(ref, value);
    final books = libraryId == null
        ? null
        : ref.watch(authorBooksProvider((source: widget.source, libraryId: libraryId, name: value.name))).value;
    final all = [...?books?.series.expand((s) => s.books), ...?books?.standalone];
    return CollectionScaffold(
      title: value.name,
      subtitle: all.isEmpty ? null : l10n.bookCountLabel(all.length),
      themeBook: all.isEmpty ? null : all.first,
      artwork: AuthorAvatar(author: value, size: 148, semanticLabel: l10n.authorPhotoLabel(value.name)),
      refreshError: refreshError,
      onRefresh: () => _refresh(force: true),
      below: value.description == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [DescriptionText(html: value.description!, maxLines: 4)],
            ),
      slivers: [
        if (books == null) const SliverToBoxAdapter(child: ShelfSkeleton()),
        for (final s in books?.series ?? const <SeriesSummary>[]) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: s.name,
              action: TextButton(
                onPressed: () => BrowseNav.series(context, s.source, s.id),
                child: Text(l10n.genericSeeAll),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: s.books.length,
            itemBuilder: (_, i) {
              final b = s.books[i];
              return BookListRow(
                book: b,
                place: 'author-${s.id}',
                leadingLabel: b.seriesSequence == null ? null : l10n.itemSeriesPosition(b.seriesSequence!, s.name),
              );
            },
          ),
        ],
        if (books != null && books.standalone.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: books.series.isEmpty ? l10n.authorBooks : l10n.authorStandalone),
          ),
          SliverList.builder(
            itemCount: books.standalone.length,
            itemBuilder: (_, i) => BookListRow(book: books.standalone[i], place: 'author'),
          ),
        ],
        if (books != null && all.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(l10n.libraryEmpty, textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  /// The library the author is in; when unknown, the current server
  /// library, else the first one.
  String? _libraryOf(WidgetRef ref, AuthorSummary author) {
    if (author.libraryId != null && author.libraryId!.isNotEmpty) return author.libraryId;
    final current = ref.watch(currentLibraryProvider).value;
    if (current != null && current.source == widget.source) return current.id;
    final libraries = ref.watch(absLibrariesProvider).value ?? const [];
    return libraries.isEmpty ? null : libraries.first.id;
  }
}
