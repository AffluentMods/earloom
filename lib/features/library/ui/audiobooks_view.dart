// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

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
import '../../../core/ui/adaptive.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../downloads/data/offline_providers.dart';
import '../../downloads/ui/bulk_download.dart';
import '../data/book_groups.dart';
import '../data/library_providers.dart';
import 'book_actions.dart';
import 'library_screen.dart' show audiobooksLayoutKey, libraryPaneProvider;
import 'library_sheets.dart';
import 'library_switcher.dart';
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';

/// Every book: the server library's and the ones on this phone in one list,
/// with the progress and download filters one tap away, then how many books
/// there are, grid or list, and the sort. Pages 50 at a time from the cache
/// while the server library syncs in the background.
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

  /// The books picked with Select, in the order picked; null when not
  /// picking.
  Map<ItemRef, BookSummary>? _picked;

  void _startPicking() => setState(() => _picked = {});

  void _stopPicking() => setState(() => _picked = null);

  void _toggle(BookSummary book) => setState(() {
    final picked = _picked;
    if (picked == null) return;
    if (picked.remove(book.ref) == null) picked[book.ref] = book;
  });

  Future<void> _downloadPicked() async {
    final picked = _picked;
    if (picked == null || picked.isEmpty) return;
    if (await downloadBooks(context, ref, [...picked.values]) && mounted) _stopPicking();
  }

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
    final count = ref.watch(audiobooksCountProvider((server: _args.server, query: _query))).value;
    final list = books.value;
    final hasMore = list != null && list.length >= _limit;
    // On wide screens the chosen book is open beside the list: mark it.
    final open = MediaQuery.sizeOf(context).width >= Breakpoints.expanded ? ref.watch(libraryPaneProvider) : null;
    final filtered = _query.filters.isNotEmpty;
    // Picking books to download: server books not on the phone yet.
    final picked = _picked;
    final onPhone = picked == null ? const <String>{} : ref.watch(downloadedBookIdsProvider).ids;
    bool pickable(BookSummary b) => b.ref.source is AbsSource && !onPhone.contains(b.ref.itemId);
    // While picking, what cannot be picked steps back and does nothing.
    Widget faded(Widget child) => picked == null ? child : IgnorePointer(child: Opacity(opacity: 0.4, child: child));
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
              BookEntry(:final book) when picked != null && !pickable(book) => faded(
                BookGridCard(book: book, width: c.maxWidth, place: 'library', markPhoneBook: library != null),
              ),
              BookEntry(:final book) => BookGridCard(
                book: book,
                width: c.maxWidth,
                place: 'library',
                selected: book.ref == open,
                markPhoneBook: library != null,
                onTap: picked == null ? null : () => _toggle(book),
                checked: picked?.containsKey(book.ref),
              ),
              GroupEntry(:final group, :final books, :final count) => faded(
                BookGroupCard(group: group, books: books, count: count, width: c.maxWidth),
              ),
            },
          ),
        ),
      );
    } else {
      body = SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => switch (list[i]) {
          BookEntry(:final book) when picked != null && !pickable(book) => faded(
            BookListRow(book: book, place: 'library', markPhoneBook: library != null),
          ),
          BookEntry(:final book) when picked != null => BookListRow(
            book: book,
            place: 'library',
            markPhoneBook: library != null,
            onTap: () => _toggle(book),
            trailing: Checkbox(value: picked.containsKey(book.ref), onChanged: (_) => _toggle(book)),
          ),
          BookEntry(:final book) => BookListRow(
            book: book,
            place: 'library',
            selected: book.ref == open,
            markPhoneBook: library != null,
            trailing: BookRowActions(book: book, libraryId: library?.id),
          ),
          GroupEntry(:final group, :final books, :final count) => faded(
            BookGroupRow(group: group, books: books, count: count),
          ),
        },
      );
    }
    final scroll = RefreshIndicator(
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
          SliverToBoxAdapter(
            child: _CountLayoutSort(
              count: count,
              grid: widget.grid,
              query: _query,
              local: library == null,
              onChanged: _setQuery,
              // Only server books can be downloaded.
              onSelect: library == null || offline || picked != null ? null : _startPicking,
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
    if (picked == null) return scroll;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopPicking();
      },
      child: Column(
        children: [
          Expanded(child: scroll),
          _PickBar(count: picked.length, onClose: _stopPicking, onDownload: picked.isEmpty ? null : _downloadPicked),
        ],
      ),
    );
  }
}

/// At the bottom of Audiobooks while picking books: how many, and
/// Download.
class _PickBar extends StatelessWidget {
  const _PickBar({required this.count, required this.onClose, required this.onDownload});

  final int count;
  final VoidCallback onClose;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(context.gutter - Space.sm, Space.sm, context.gutter, Space.sm),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.close_rounded), tooltip: l10n.librarySelectStop, onPressed: onClose),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(l10n.librarySelectedCount(count), style: theme.textTheme.titleMedium),
              ),
            ),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              label: Text(l10n.downloadAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chips above the books: More filters, then one-tap chips for
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

/// Under the chips: how many books, grid or list, and the sort. The sort
/// moves to its own line when the text is large.
class _CountLayoutSort extends ConsumerWidget {
  const _CountLayoutSort({
    required this.count,
    required this.grid,
    required this.query,
    required this.local,
    required this.onChanged,
    this.onSelect,
  });

  /// Null while counting.
  final int? count;
  final bool grid;
  final LibraryQuery query;
  final bool local;
  final ValueChanged<LibraryQuery> onChanged;

  /// Starts picking books to download; null hides Select.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final sort = librarySortLabel(l10n, query.sort);
    final direction = query.descending ? l10n.librarySortDescending : l10n.librarySortAscending;
    final layoutLabel = grid ? l10n.libraryList : l10n.libraryGrid;
    return Padding(
      padding: EdgeInsets.fromLTRB(context.gutter, 0, context.gutter - Space.sm, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null) ...[
                Text(l10n.bookCountLabel(count!), style: text.titleMedium),
                const SizedBox(width: Space.sm),
              ],
              Tooltip(
                message: layoutLabel,
                child: TextButton.icon(
                  icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                  label: Text(grid ? l10n.libraryLayoutList : l10n.libraryLayoutGrid),
                  onPressed: () => ref
                      .read(globalDbProvider)
                      .writeSetting('${LibrarySettingKeys.layoutPrefix}$audiobooksLayoutKey', grid ? 'list' : 'grid'),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: l10n.librarySort,
                child: Semantics(
                  label: l10n.librarySortedBy(sort, direction),
                  button: true,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    icon: Icon(query.descending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                    label: Text(sort),
                    onPressed: () async {
                      final next = await showSortSheet(context, query, local: local);
                      if (next != null) onChanged(next);
                    },
                  ),
                ),
              ),
              if (onSelect != null) TextButton(onPressed: onSelect, child: Text(l10n.librarySelect)),
            ],
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
  FilterKind.downloaded =>
    f.value == DownloadFilterValue.notDownloaded ? l10n.filterNotDownloaded : l10n.filterDownloaded,
  _ => f.label,
};
