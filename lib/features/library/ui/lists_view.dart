// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/adaptive.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/favorites.dart';
import '../data/library_providers.dart';
import '../data/library_repository.dart';
import 'book_actions.dart';
import 'browse_nav.dart';
import 'widgets/book_cards.dart';
import 'browse_not_found.dart';
import 'widgets/browse_layout.dart';

/// The lists the Lists tab opens, by their path segment.
enum LibraryList {
  favorites,
  series,
  authors,
  collections,
  playlists;

  /// Server libraries have collections and playlists; this phone does not.
  bool get serverOnly => this == collections || this == playlists;
}

/// The Lists tab: one row per list, each with how much is in it. A row
/// opens the list as its own screen.
class ListsView extends ConsumerWidget {
  const ListsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(audiobooksLibraryProvider);
    final server = library == null ? null : libraryKeyOf(library);
    int? count<T>(AsyncValue<List<T>> value) => value.value?.length;
    final counts = {
      LibraryList.favorites: count(ref.watch(favoriteBooksProvider)),
      LibraryList.series: count(ref.watch(mixedSeriesProvider(server))),
      LibraryList.authors: count(ref.watch(mixedAuthorsProvider(server))),
      if (server != null) ...{
        LibraryList.collections: count(ref.watch(collectionsProvider(server))),
        LibraryList.playlists: count(ref.watch(playlistsProvider(server))),
      },
    };
    String? subtitle(LibraryList list, int? n) => n == null
        ? null
        : switch (list) {
            LibraryList.favorites => l10n.bookCountLabel(n),
            LibraryList.series => l10n.listsSeriesCount(n),
            LibraryList.authors => l10n.listsAuthorsCount(n),
            LibraryList.collections => l10n.listsCollectionsCount(n),
            LibraryList.playlists => l10n.listsPlaylistsCount(n),
          };
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.only(top: Space.sm, bottom: MediaQuery.paddingOf(context).bottom + Space.xl),
      children: [
        for (final list in LibraryList.values)
          if (!list.serverOnly || server != null)
            ListTile(
              minTileHeight: 72,
              contentPadding: EdgeInsets.symmetric(horizontal: context.gutter),
              leading: CircleAvatar(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
                child: Icon(libraryListIcon(list)),
              ),
              title: Text(libraryListTitle(l10n, list)),
              subtitle: switch (subtitle(list, counts[list])) {
                final text? => Text(text),
                null => null,
              },
              trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              onTap: () => context.push(AppRoutes.libraryList(list.name)),
            ),
      ],
    );
  }
}

String libraryListTitle(AppLocalizations l10n, LibraryList list) => switch (list) {
  LibraryList.favorites => l10n.listsFavorites,
  LibraryList.series => l10n.librarySeries,
  LibraryList.authors => l10n.libraryAuthors,
  LibraryList.collections => l10n.libraryCollections,
  LibraryList.playlists => l10n.libraryPlaylists,
};

IconData libraryListIcon(LibraryList list) => switch (list) {
  LibraryList.favorites => Icons.favorite_rounded,
  LibraryList.series => Icons.auto_stories_rounded,
  LibraryList.authors => Icons.person_rounded,
  LibraryList.collections => Icons.collections_bookmark_rounded,
  LibraryList.playlists => Icons.queue_music_rounded,
};

/// One list of the Lists tab, full screen. [name] is the path segment;
/// an unknown one shows the not found screen.
class LibraryListScreen extends StatelessWidget {
  const LibraryListScreen({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final list = LibraryList.values.asNameMap()[name];
    if (list == null) return const BrowseNotFound();
    return Scaffold(
      appBar: AppBar(title: Text(libraryListTitle(AppLocalizations.of(context), list))),
      body: switch (list) {
        LibraryList.favorites => const _FavoritesList(),
        LibraryList.series => const _SeriesList(),
        LibraryList.authors => const _AuthorsList(),
        LibraryList.collections => const _BookLists(playlists: false),
        LibraryList.playlists => const _BookLists(playlists: true),
      },
    );
  }
}

/// The repository for [source], when it is the current account.
AbsLibraryRepository? _repositoryFor(WidgetRef ref, SourceId? source) {
  final repository = ref.read(absLibraryRepositoryProvider);
  return repository != null && repository.source == source ? repository : null;
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(favoriteBooksProvider).value;
    if (books == null) return const CustomScrollView(slivers: [SliverGridSkeleton()]);
    if (books.isEmpty) {
      return EmptyState(icon: Icons.favorite_border_rounded, title: l10n.favoritesEmpty, body: l10n.favoritesEmptyBody);
    }
    final mixed = ref.watch(audiobooksLibraryProvider) != null;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(context.gutter, Space.md, context.gutter, Space.xl),
          sliver: SliverGrid.builder(
            gridDelegate: bookGridDelegate(context),
            itemCount: books.length,
            itemBuilder: (context, i) => LayoutBuilder(
              builder: (context, c) =>
                  BookGridCard(book: books[i], width: c.maxWidth, place: 'favorites', markPhoneBook: mixed),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeriesList extends ConsumerStatefulWidget {
  const _SeriesList();

  @override
  ConsumerState<_SeriesList> createState() => _SeriesListState();
}

class _SeriesListState extends ConsumerState<_SeriesList> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final library = ref.read(audiobooksLibraryProvider);
    final repository = _repositoryFor(ref, library?.source);
    if (library == null || repository == null) return;
    await runRefresh(() => repository.refreshSeriesList(library.id, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(audiobooksLibraryProvider);
    final list = ref.watch(mixedSeriesProvider(library == null ? null : libraryKeyOf(library))).value;
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (list == null)
            const SliverGridSkeleton()
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.auto_stories_outlined, title: l10n.libraryEmptySeries),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(context.gutter, Space.lg, context.gutter, Space.xl),
              sliver: SliverGrid.builder(
                gridDelegate: bookGridDelegate(context),
                itemCount: list.length,
                itemBuilder: (context, i) => LayoutBuilder(
                  builder: (context, c) => SeriesCard(series: list[i], width: c.maxWidth),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthorsList extends ConsumerStatefulWidget {
  const _AuthorsList();

  @override
  ConsumerState<_AuthorsList> createState() => _AuthorsListState();
}

class _AuthorsListState extends ConsumerState<_AuthorsList> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final library = ref.read(audiobooksLibraryProvider);
    final repository = _repositoryFor(ref, library?.source);
    if (library == null || repository == null) return;
    await runRefresh(() => repository.refreshAuthors(library.id, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(audiobooksLibraryProvider);
    final list = ref.watch(mixedAuthorsProvider(library == null ? null : libraryKeyOf(library))).value;
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (list == null)
            const SliverGridSkeleton()
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.person_outline_rounded, title: l10n.libraryEmptyAuthors),
            )
          else
            // Rows, not a grid: names get the whole width and are never cut.
            SliverPadding(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xl),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => AuthorRow(author: list[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Collections or playlists of the server library.
class _BookLists extends ConsumerStatefulWidget {
  const _BookLists({required this.playlists});

  final bool playlists;

  @override
  ConsumerState<_BookLists> createState() => _BookListsState();
}

class _BookListsState extends ConsumerState<_BookLists> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final library = ref.read(audiobooksLibraryProvider);
    final repository = _repositoryFor(ref, library?.source);
    if (library == null || repository == null) return;
    await runRefresh(
      () => widget.playlists
          ? repository.refreshPlaylists(library.id, force: force)
          : repository.refreshCollections(library.id, force: force),
    );
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final library = ref.read(audiobooksLibraryProvider);
    final repository = _repositoryFor(ref, library?.source);
    final name = await askName(context, title: l10n.playlistNew, confirm: l10n.genericCreate);
    if (name == null || library == null || repository == null || !mounted) return;
    try {
      final id = await repository.createPlaylist(library.id, name);
      if (mounted && id.isNotEmpty) BrowseNav.playlist(context, library.source, id);
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final library = ref.watch(audiobooksLibraryProvider);
    if (library == null) return const BrowseNotFound();
    final key = libraryKeyOf(library);
    final list = ref.watch(widget.playlists ? playlistsProvider(key) : collectionsProvider(key)).value;
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (widget.playlists)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.gutter, Space.md, context.gutter, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.playlistNew),
                  ),
                ),
              ),
            ),
          if (list == null)
            const SliverToBoxAdapter(child: ShelfSkeleton())
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: widget.playlists ? Icons.queue_music_rounded : Icons.collections_bookmark_outlined,
                title: widget.playlists ? l10n.libraryEmptyPlaylists : l10n.libraryEmptyCollections,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final item = list[i];
                  return InkWell(
                    onTap: () => widget.playlists
                        ? BrowseNav.playlist(context, item.source, item.id)
                        : BrowseNav.collection(context, item.source, item.id),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.gutter, vertical: Space.md),
                      child: Row(
                        children: [
                          CoverStack(books: item.books, size: 72),
                          const SizedBox(width: Space.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text(
                                  l10n.bookCountLabel(item.books.length),
                                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
