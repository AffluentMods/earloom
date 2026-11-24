// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/adaptive.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../downloads/data/offline_providers.dart';
import '../data/book_groups.dart';
import '../data/library_providers.dart';
import 'library_screen.dart' show libraryPaneProvider;
import 'library_sheets.dart';
import 'library_switcher.dart';
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';

/// Every book: the server library's and the ones on this phone in one list,
/// with the progress and download filters one tap away. Pages 50 at a time
/// from the cache while the server library syncs in the background.
class AudiobooksView extends ConsumerStatefulWidget {
  const AudiobooksView({super.key, required this.grid});

  final bool grid;

  @override
  ConsumerState<AudiobooksView> createState() => _AudiobooksViewState();
}

class _AudiobooksViewState extends ConsumerState<AudiobooksView> with RefreshingState, AutomaticKeepAliveClientMixin {
  static const _page = 50;
  int _limit = _page;
  bool _syncing = false;
  LibraryQuery _query = const LibraryQuery();
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // Another server library: its own sync, from the top.
    ref.listenManual(audiobooksLibraryProvider.select((l) => l?.id), (previous, next) {
      if (previous == next) return;
      setState(() => _limit = _page);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _sync();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setQuery(LibraryQuery query) {
    setState(() {
      _query = query;
      _limit = _page;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _sync({bool force = false}) async {
    final library = ref.read(audiobooksLibraryProvider);
    final repository = ref.read(absLibraryRepositoryProvider);
    if (library == null || repository == null || repository.source != library.source) return;
    if (mounted) setState(() => _syncing = true);
    await runRefresh(() async {
      await repository.syncLibrary(library.id, force: force);
      if (force) await repository.refreshProgress();
      // A grouped series' card needs to know its books, also new ones.
      // (An author's books are known from the library sync itself.)
      for (final g in ref.read(bookGroupsProvider).value ?? const <BookGroup>[]) {
        if (g.kind == BookGroupKind.series && g.source == library.source && g.libraryId == library.id) {
          await repository.refreshSeries(g.id, force: force);
        }
      }
    });
    if (mounted) setState(() => _syncing = false);
  }

  /// Loads the next page once the user is 70% of the way down.
  void _onScroll() {
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels / position.maxScrollExtent < 0.7) return;
    final shown = ref.read(audiobooksProvider(_args)).value?.length ?? 0;
    if (shown >= _limit) setState(() => _limit += _page);
  }

  AudiobooksArgs get _args {
    final library = ref.read(audiobooksLibraryProvider);
    return (server: library == null ? null : libraryKeyOf(library), query: _query, limit: _limit);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(audiobooksLibraryProvider);
    final libraries = ref.watch(bookLibrariesProvider);
    final offline = ref.watch(isOfflineProvider);
    final books = ref.watch(audiobooksProvider(_args));
    final list = books.value;
    final hasMore = list != null && list.length >= _limit;
    // On wide screens the chosen book is open beside the list: mark it.
    final open = MediaQuery.sizeOf(context).width >= Breakpoints.expanded ? ref.watch(libraryPaneProvider) : null;
    final filtered = _query.filters.isNotEmpty;
    Widget body;
    if (list == null || (list.isEmpty && _syncing && !filtered)) {
      body = const SliverGridSkeleton();
    } else if (list.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: filtered
            ? EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: l10n.libraryEmptyFiltered,
                action: OutlinedButton(
                  onPressed: () => _setQuery(_query.copyWith(filters: const [])),
                  child: Text(l10n.filterClearAll),
                ),
              )
            : offline
            ? EmptyState(
                icon: Icons.cloud_off_rounded,
                title: l10n.libraryOfflineEmpty,
                body: l10n.libraryOfflineEmptyBody,
              )
            : library == null
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
        padding: EdgeInsets.fromLTRB(context.gutter, Space.md, context.gutter, Space.lg),
        sliver: SliverGrid.builder(
          gridDelegate: bookGridDelegate(context),
          itemCount: list.length,
          itemBuilder: (context, i) => LayoutBuilder(
            builder: (context, c) => switch (list[i]) {
              BookEntry(:final book) => BookGridCard(
                book: book,
                width: c.maxWidth,
                place: 'library',
                selected: book.ref == open,
                markPhoneBook: library != null,
              ),
              GroupEntry(:final group, :final books, :final count) => BookGroupCard(
                group: group,
                books: books,
                count: count,
                width: c.maxWidth,
              ),
            },
          ),
        ),
      );
    } else {
      body = SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => switch (list[i]) {
          BookEntry(:final book) => BookListRow(
            book: book,
            place: 'library',
            selected: book.ref == open,
            markPhoneBook: library != null,
          ),
          GroupEntry(:final group, :final books, :final count) => BookGroupRow(
            group: group,
            books: books,
            count: count,
          ),
        },
      );
    }
    return RefreshIndicator(
      onRefresh: () => _sync(force: true),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          // More than one server book library: which one is mixed in here.
          if (library != null && libraries.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.gutter - Space.sm, Space.sm, context.gutter, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: LibrarySwitcherButton(library: library, only: (l) => l.source is AbsSource && !l.isPodcast),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: QuickFilterBar(
              query: _query,
              offline: offline,
              filterKey: library == null ? libraryKeyOf(localLibrary) : libraryKeyOf(library),
              local: library == null,
              onChanged: _setQuery,
            ),
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

/// The row above the books: sort, More filters, then one-tap chips for
/// progress (not started, in progress, finished) and downloads (downloaded,
/// not downloaded), then each filter from the sheet as a removable chip.
class QuickFilterBar extends StatelessWidget {
  const QuickFilterBar({
    super.key,
    required this.query,
    required this.filterKey,
    required this.onChanged,
    this.offline = false,
    this.local = false,
  });

  final LibraryQuery query;

  /// The library whose genres, series and people the sheet offers.
  final LibraryKey filterKey;
  final ValueChanged<LibraryQuery> onChanged;

  /// Offline only books on this phone are listed, so the download chips
  /// would mean nothing.
  final bool offline;

  /// Only books on this phone (no server): every book is downloaded.
  final bool local;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sort = librarySortLabel(l10n, query.sort);
    final direction = query.descending ? l10n.librarySortDescending : l10n.librarySortAscending;
    final more = query.moreFilters;
    Widget quick(LibraryFilter filter) {
      final selected = query.filterOf(filter.kind) == filter;
      return Padding(
        padding: const EdgeInsets.only(left: Space.sm),
        child: FilterChip(
          label: Text(filterChipLabel(l10n, filter)),
          selected: selected,
          onSelected: (_) => onChanged(selected ? query.without(filter) : query.withFilter(filter)),
        ),
      );
    }

    // Outline, not the faint default: these are controls and need 3:1.
    // A short row, built whole so every chip can be scrolled to.
    return ChipTheme(
      data: ChipTheme.of(context).copyWith(side: BorderSide(color: scheme.outline)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.gutter, vertical: Space.sm),
        child: Row(
          children: [
            Semantics(
              label: l10n.librarySortedBy(sort, direction),
              excludeSemantics: true,
              button: true,
              child: ActionChip(
                avatar: Icon(query.descending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                label: Text(sort),
                tooltip: l10n.librarySort,
                onPressed: () async {
                  final next = await showSortSheet(context, query, local: local);
                  if (next != null) onChanged(next);
                },
              ),
            ),
            const SizedBox(width: Space.sm),
            ActionChip(
              avatar: const Icon(Icons.tune_rounded),
              label: Text(
                more.isEmpty
                    ? l10n.libraryMoreFilters
                    : l10n.libraryMoreFiltersCount(NumberFormat.decimalPattern(l10n.localeName).format(more.length)),
              ),
              tooltip: l10n.libraryMoreFilters,
              onPressed: () async {
                final next = await showFilterSheet(context, filterKey, query);
                if (next != null) onChanged(next);
              },
            ),
            // What the sheet set, each removable, next to the chip that set it.
            for (final f in more) ...[
              const SizedBox(width: Space.sm),
              InputChip(
                label: Text(filterChipLabel(l10n, f)),
                onDeleted: () => onChanged(query.without(f)),
                deleteButtonTooltipMessage: l10n.filterRemove(filterChipLabel(l10n, f)),
              ),
            ],
            for (final value in const [
              ProgressFilterValue.notStarted,
              ProgressFilterValue.inProgress,
              ProgressFilterValue.finished,
            ])
              quick(LibraryFilter(FilterKind.progress, value)),
            if (!offline && !local)
              for (final value in const [DownloadFilterValue.downloaded, DownloadFilterValue.notDownloaded])
                quick(LibraryFilter(FilterKind.downloaded, value)),
            if (query.filters.isNotEmpty) ...[
              const SizedBox(width: Space.xs),
              TextButton(
                onPressed: () => onChanged(query.copyWith(filters: const [])),
                child: Text(l10n.filterClearAll),
              ),
            ],
          ],
        ),
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
  FilterKind.downloaded =>
    f.value == DownloadFilterValue.notDownloaded ? l10n.filterNotDownloaded : l10n.filterDownloaded,
  _ => f.label,
};
