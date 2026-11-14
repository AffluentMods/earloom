// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../podcasts/ui/podcast_library_screen.dart';
import '../data/library_providers.dart';
import '../data/library_repository.dart';
import 'book_actions.dart';
import 'browse_nav.dart';
import 'library_sheets.dart';
import 'library_switcher.dart';
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';

/// The sections of the Library tab.
enum LibrarySection { books, series, authors, collections, playlists }

/// The Library tab: the current library (a server library or On this
/// device) as books, series, authors, collections and playlists.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(currentLibraryProvider);
    final value = library.value;
    if (value == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).tabLibrary)),
        body: const CustomScrollView(slivers: [SliverGridSkeleton()]),
      );
    }
    // A new library starts with its own sort, filters and scroll position.
    if (value.isPodcast && value.source is AbsSource) {
      return PodcastLibraryScreen(key: ValueKey(selectionKey(value)), library: value);
    }
    return _LibraryView(key: ValueKey(selectionKey(value)), library: value);
  }
}

class _LibraryView extends ConsumerStatefulWidget {
  const _LibraryView({super.key, required this.library});

  final LibraryInfo library;

  @override
  ConsumerState<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<_LibraryView> with TickerProviderStateMixin {
  late final List<LibrarySection> _sections = widget.library.source is LocalSource
      ? const [LibrarySection.books, LibrarySection.series, LibrarySection.authors]
      : LibrarySection.values;
  late final TabController _tabs = TabController(length: _sections.length, vsync: this)
    ..addListener(() => setState(() {}));
  LibraryQuery _query = const LibraryQuery();

  LibraryKey get _key => libraryKeyOf(widget.library);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _sectionLabel(AppLocalizations l10n, LibrarySection s) => switch (s) {
    LibrarySection.books => l10n.libraryBooks,
    LibrarySection.series => l10n.librarySeries,
    LibrarySection.authors => l10n.libraryAuthors,
    LibrarySection.collections => l10n.libraryCollections,
    LibrarySection.playlists => l10n.libraryPlaylists,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grid = ref.watch(gridLayoutProvider(selectionKey(widget.library))).value ?? true;
    final onBooks = _sections[_tabs.index] == LibrarySection.books;
    final isLocal = widget.library.source is LocalSource;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.sm,
        title: LibrarySwitcherButton(library: widget.library, large: true),
        actions: [
          if (onBooks) ...[
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: l10n.librarySort,
              onPressed: () async {
                final next = await showSortSheet(context, _query, local: isLocal);
                if (next != null) setState(() => _query = next);
              },
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: _query.filters.isNotEmpty,
                label: Text(NumberFormat.decimalPattern(l10n.localeName).format(_query.filters.length)),
                child: const Icon(Icons.filter_list_rounded),
              ),
              tooltip: _query.filters.isEmpty ? l10n.libraryFilter : l10n.libraryFilterCount(_query.filters.length),
              onPressed: () async {
                final next = await showFilterSheet(context, _key, _query);
                if (next != null) setState(() => _query = next);
              },
            ),
            IconButton(
              icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
              tooltip: grid ? l10n.libraryList : l10n.libraryGrid,
              onPressed: () => ref
                  .read(globalDbProvider)
                  .writeSetting(
                    '${LibrarySettingKeys.layoutPrefix}${selectionKey(widget.library)}',
                    grid ? 'list' : 'grid',
                  ),
            ),
          ],
          if (isLocal)
            IconButton(
              icon: const Icon(Icons.library_add_outlined),
              tooltip: l10n.homeAddFiles,
              onPressed: () => context.push(AppRoutes.importFiles),
            ),
          const SizedBox(width: Space.xs),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final s in _sections) Tab(text: _sectionLabel(l10n, s))],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final s in _sections)
            switch (s) {
              LibrarySection.books => _BooksView(
                library: widget.library,
                query: _query,
                grid: grid,
                onQuery: (q) => setState(() => _query = q),
              ),
              LibrarySection.series => _SeriesView(libraryKey: _key),
              LibrarySection.authors => _AuthorsView(libraryKey: _key),
              LibrarySection.collections => _ListsView(libraryKey: _key, playlists: false),
              LibrarySection.playlists => _ListsView(libraryKey: _key, playlists: true),
            },
        ],
      ),
    );
  }
}

/// All books with sort and filters, as a grid or a list. Pages 50 at a time
/// from the cache while the library syncs in the background.
class _BooksView extends ConsumerStatefulWidget {
  const _BooksView({required this.library, required this.query, required this.grid, required this.onQuery});

  final LibraryInfo library;
  final LibraryQuery query;
  final bool grid;
  final ValueChanged<LibraryQuery> onQuery;

  @override
  ConsumerState<_BooksView> createState() => _BooksViewState();
}

class _BooksViewState extends ConsumerState<_BooksView> with RefreshingState, AutomaticKeepAliveClientMixin {
  static const _page = 50;
  int _limit = _page;
  bool _syncing = false;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(_BooksView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _limit = _page;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _sync({bool force = false}) async {
    final repository = _repositoryFor(ref, widget.library.source);
    if (repository == null) return;
    if (mounted) setState(() => _syncing = true);
    await runRefresh(() async {
      await repository.syncLibrary(widget.library.id, force: force);
      if (force) await repository.refreshProgress();
    });
    if (mounted) setState(() => _syncing = false);
  }

  /// Loads the next page once the user is 70% of the way down.
  void _onScroll() {
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels / position.maxScrollExtent < 0.7) return;
    final shown = ref.read(libraryBooksProvider(_args)).value?.length ?? 0;
    if (shown >= _limit) setState(() => _limit += _page);
  }

  BooksArgs get _args =>
      (source: widget.library.source, libraryId: widget.library.id, query: widget.query, limit: _limit);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(libraryBooksProvider(_args));
    final list = books.value;
    final isLocal = widget.library.source is LocalSource;
    final hasMore = list != null && list.length >= _limit;
    Widget body;
    if (list == null || (list.isEmpty && _syncing && widget.query.filters.isEmpty)) {
      body = const SliverGridSkeleton();
    } else if (list.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: widget.query.filters.isNotEmpty
            ? EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: l10n.libraryEmptyFiltered,
                action: OutlinedButton(
                  onPressed: () => widget.onQuery(widget.query.copyWith(filters: const [])),
                  child: Text(l10n.filterClearAll),
                ),
              )
            : isLocal
            ? EmptyState(
                icon: Icons.phone_iphone_rounded,
                title: l10n.libraryEmptyLocal,
                body: l10n.libraryEmptyLocalBody,
                action: FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.importFiles),
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(l10n.homeAddFiles),
                ),
              )
            : EmptyState(icon: Icons.auto_stories_outlined, title: l10n.libraryEmpty),
      );
    } else if (widget.grid) {
      body = SliverPadding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
        sliver: SliverGrid.builder(
          gridDelegate: bookGridDelegate(context),
          itemCount: list.length,
          itemBuilder: (context, i) => LayoutBuilder(
            builder: (context, c) => BookGridCard(book: list[i], width: c.maxWidth, place: 'library'),
          ),
        ),
      );
    } else {
      body = SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => BookListRow(book: list[i], place: 'library'),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _sync(force: true),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (widget.query.filters.isNotEmpty)
            SliverToBoxAdapter(
              child: _ActiveFilters(query: widget.query, onChanged: widget.onQuery),
            ),
          body,
          if (hasMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Center(
                  child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              ),
            )
          else if (list != null && list.length > 24)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  l10n.libraryEndOfList,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The repository for [source], when it is the current account.
AbsLibraryRepository? _repositoryFor(WidgetRef ref, SourceId source) {
  final repository = ref.read(absLibraryRepositoryProvider);
  return repository != null && repository.source == source ? repository : null;
}

/// Removable chips for the active filters, plus Clear all.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.onChanged});

  final LibraryQuery query;
  final ValueChanged<LibraryQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
        children: [
          for (final f in query.filters) ...[
            InputChip(
              label: Text(filterChipLabel(l10n, f)),
              onDeleted: () => onChanged(query.without(f)),
              deleteButtonTooltipMessage: l10n.filterRemove(filterChipLabel(l10n, f)),
            ),
            const SizedBox(width: Space.sm),
          ],
          TextButton(
            onPressed: () => onChanged(query.copyWith(filters: const [])),
            child: Text(l10n.filterClearAll),
          ),
        ],
      ),
    );
  }
}

class _SeriesView extends ConsumerStatefulWidget {
  const _SeriesView({required this.libraryKey});

  final LibraryKey libraryKey;

  @override
  ConsumerState<_SeriesView> createState() => _SeriesViewState();
}

class _SeriesViewState extends ConsumerState<_SeriesView> with RefreshingState, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = _repositoryFor(ref, widget.libraryKey.source);
    if (repository == null) return;
    await runRefresh(() => repository.refreshSeriesList(widget.libraryKey.libraryId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final series = ref.watch(seriesListProvider(widget.libraryKey));
    final list = series.value;
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
              padding: const EdgeInsets.all(Space.lg),
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

class _AuthorsView extends ConsumerStatefulWidget {
  const _AuthorsView({required this.libraryKey});

  final LibraryKey libraryKey;

  @override
  ConsumerState<_AuthorsView> createState() => _AuthorsViewState();
}

class _AuthorsViewState extends ConsumerState<_AuthorsView> with RefreshingState, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = _repositoryFor(ref, widget.libraryKey.source);
    if (repository == null) return;
    await runRefresh(() => repository.refreshAuthors(widget.libraryKey.libraryId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final authors = ref.watch(authorsListProvider(widget.libraryKey));
    final list = authors.value;
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
            SliverPadding(
              padding: const EdgeInsets.all(Space.lg),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  mainAxisSpacing: Space.lg,
                  crossAxisSpacing: Space.md,
                  childAspectRatio: 0.7,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) => LayoutBuilder(
                  builder: (context, c) => AuthorCard(author: list[i], width: c.maxWidth),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListsView extends ConsumerStatefulWidget {
  const _ListsView({required this.libraryKey, required this.playlists});

  final LibraryKey libraryKey;
  final bool playlists;

  @override
  ConsumerState<_ListsView> createState() => _ListsViewState();
}

class _ListsViewState extends ConsumerState<_ListsView> with RefreshingState, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = _repositoryFor(ref, widget.libraryKey.source);
    if (repository == null) return;
    final id = widget.libraryKey.libraryId;
    await runRefresh(
      () => (widget.playlists
          ? repository.refreshPlaylists(id, force: force)
          : repository.refreshCollections(id, force: force)),
    );
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(absLibraryRepositoryProvider);
    final name = await askName(context, title: l10n.playlistNew, confirm: l10n.genericCreate);
    if (name == null || repository == null || !mounted) return;
    try {
      final id = await repository.createPlaylist(widget.libraryKey.libraryId, name);
      if (mounted && id.isNotEmpty) BrowseNav.playlist(context, widget.libraryKey.source, id);
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lists = ref.watch(
      widget.playlists ? playlistsProvider(widget.libraryKey) : collectionsProvider(widget.libraryKey),
    );
    final list = lists.value;
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (widget.playlists)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
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
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
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

/// What a filter chip says.
String filterChipLabel(AppLocalizations l10n, LibraryFilter f) => switch (f.kind) {
  FilterKind.progress => switch (f.value) {
    ProgressFilterValue.finished => l10n.filterFinished,
    ProgressFilterValue.inProgress => l10n.filterInProgress,
    _ => l10n.filterNotStarted,
  },
  FilterKind.downloaded => l10n.filterDownloadedOnly,
  _ => f.label,
};
