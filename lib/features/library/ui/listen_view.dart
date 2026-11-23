// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/adaptive.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../downloads/data/download_manager.dart';
import '../../downloads/data/offline_providers.dart';
import '../../downloads/ui/download_rows.dart';
import '../data/library_providers.dart';
import 'browse_nav.dart';
import 'library_screen.dart' show libraryPaneProvider;
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';

/// The settings key of the Listen tab's Downloaded only switch.
const listenDownloadedOnlyKey = 'library.listen.downloadedOnly';

/// Whether the Listen tab shows only what is on this phone.
final listenDownloadedOnlyProvider = StreamProvider<bool>(
  (ref) => ref.watch(globalDbProvider).watchSetting(listenDownloadedOnlyKey).map((v) => v == 'true'),
);

/// The current account's downloaded books, most recently downloaded first.
final listenDownloadedBooksProvider = StreamProvider.autoDispose<List<BookSummary>>((ref) {
  final repository = ref.watch(absLibraryRepositoryProvider);
  final ids = ref.watch(downloadedBookIdsProvider);
  if (repository == null || ids.ids.isEmpty) return Stream.value(const []);
  // The order only: reading it does not rebuild on every progress tick.
  final states = ref.read(downloadStatesProvider).value ?? const <String, DownloadState>{};
  final done = {
    for (final s in states.values)
      if (s.isComplete && s.ref.episodeId == null && ids.contains(s.ref.itemId)) s.ref.itemId: s.completedAt,
  };
  final ordered = ids.ids.toList()..sort((a, b) => (done[b] ?? DateTime(0)).compareTo(done[a] ?? DateTime(0)));
  return repository.watchBooksByIds(ordered);
});

/// Downloads that are not finished, on any account: they are on this phone.
List<DownloadState> unfinishedDownloads(Map<String, DownloadState>? states) => [
  for (final s in states?.values ?? const <DownloadState>[])
    if (s.phase != DownloadPhase.none && s.phase != DownloadPhase.complete) s,
]..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));

/// Downloaded podcast episodes of the current account, newest first.
List<DownloadState> downloadedEpisodes(Map<String, DownloadState>? states, SourceId? source) => [
  for (final s in states?.values ?? const <DownloadState>[])
    if (s.isComplete && s.ref.episodeId != null && s.ref.source == source) s,
]..sort((a, b) => (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0)));

/// What to listen to now: downloads still running (with Pause and Cancel),
/// books in progress, and what is downloaded.
class ListenView extends ConsumerStatefulWidget {
  const ListenView({super.key, required this.onBrowse});

  /// Opens the Audiobooks tab, from the empty state.
  final VoidCallback onBrowse;

  @override
  ConsumerState<ListenView> createState() => _ListenViewState();
}

class _ListenViewState extends ConsumerState<ListenView> with RefreshingState, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null) return;
    await runRefresh(repository.refreshProgress);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final offline = ref.watch(isOfflineProvider);
    final source = ref.watch(absLibraryRepositoryProvider.select((r) => r?.source));
    // Without a server, or while it cannot be reached, everything listed
    // is on this phone: the switch would change nothing.
    final canFilter = source != null && !offline;
    final downloadedOnly = canFilter && (ref.watch(listenDownloadedOnlyProvider).value ?? false);
    // Counts and keys, so progress ticks of a running download rebuild only
    // the Downloading rows below.
    final running = ref.watch(downloadStatesProvider.select((v) => unfinishedDownloads(v.value).length));
    final episodeKeys = ref.watch(
      downloadStatesProvider.select((v) => [for (final s in downloadedEpisodes(v.value, source)) s.key].join(',')),
    );
    final episodes = episodeKeys.isEmpty
        ? const <DownloadState>[]
        : downloadedEpisodes(ref.read(downloadStatesProvider).value, source);
    final continuing = ref.watch(continueListeningProvider);
    final downloaded = ref.watch(listenDownloadedBooksProvider);
    final onPhone = ref.watch(downloadedBookIdsProvider);
    final open = MediaQuery.sizeOf(context).width >= Breakpoints.expanded ? ref.watch(libraryPaneProvider) : null;

    final loading = !continuing.hasValue || !downloaded.hasValue;
    final inProgress = [
      for (final b in continuing.value ?? const <BookSummary>[])
        if (!downloadedOnly || b.ref.source is LocalSource || onPhone.contains(b.ref.itemId)) b,
    ];
    final started = {for (final b in inProgress) b.ref};
    // A book in progress shows once, under Continue listening.
    final saved = [
      for (final b in downloaded.value ?? const <BookSummary>[])
        if (!started.contains(b.ref)) b,
    ];
    final empty = !loading && running == 0 && inProgress.isEmpty && saved.isEmpty && episodes.isEmpty;

    Widget title(String text) => SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(context.gutter, Space.xl, context.gutter, Space.sm),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.sectionTitle),
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          if (canFilter)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.gutter, Space.sm, context.gutter, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilterChip(
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    label: Text(l10n.filterDownloadedOnly),
                    selected: downloadedOnly,
                    onSelected: (on) =>
                        ref.read(globalDbProvider).writeSetting(listenDownloadedOnlyKey, on ? 'true' : 'false'),
                  ),
                ),
              ),
            ),
          if (running > 0) ...[title(l10n.listenDownloading), const _DownloadingRows()],
          if (loading)
            const SliverToBoxAdapter(child: ShelfSkeleton())
          else if (empty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: downloadedOnly
                  ? EmptyState(
                      icon: Icons.download_for_offline_outlined,
                      title: l10n.listenNothingDownloaded,
                      body: l10n.listenNothingDownloadedBody,
                      action: OutlinedButton(onPressed: widget.onBrowse, child: Text(l10n.listenBrowse)),
                    )
                  : EmptyState(
                      icon: Icons.headphones_rounded,
                      title: l10n.listenEmptyTitle,
                      body: l10n.listenEmptyBody,
                      action: FilledButton(onPressed: widget.onBrowse, child: Text(l10n.listenBrowse)),
                    ),
            )
          else ...[
            if (inProgress.isNotEmpty) ...[
              title(l10n.homeContinueListening),
              SliverList.builder(
                itemCount: inProgress.length,
                itemBuilder: (_, i) =>
                    BookListRow(book: inProgress[i], place: 'listen', selected: inProgress[i].ref == open),
              ),
            ],
            if (saved.isNotEmpty || episodes.isNotEmpty) ...[
              title(l10n.listenDownloaded),
              SliverList.builder(
                itemCount: saved.length,
                itemBuilder: (_, i) =>
                    BookListRow(book: saved[i], place: 'listen-saved', selected: saved[i].ref == open),
              ),
              SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (_, i) => _EpisodeRow(state: episodes[i]),
              ),
            ],
          ],
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xl)),
        ],
      ),
    );
  }
}

/// The unfinished downloads with their buttons. Rebuilds on every progress
/// tick, on its own.
class _DownloadingRows extends ConsumerWidget {
  const _DownloadingRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = unfinishedDownloads(ref.watch(downloadStatesProvider).value);
    final current = ref.watch(absLibraryRepositoryProvider.select((r) => r?.source));
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final state = rows[i];
        final mine = state.ref.source == current;
        return ActiveDownloadRow(
          state: state,
          onTap: !mine
              ? null
              : state.ref.episodeId == null
              ? () => BrowseNav.book(context, state.ref)
              : () => BrowseNav.show(context, ItemRef(state.ref.source, state.ref.itemId)),
        );
      },
    );
  }
}

/// A downloaded podcast episode: its cover, title and show. Opens the show.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.state});

  final DownloadState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => BrowseNav.show(context, ItemRef(state.ref.source, state.ref.itemId)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
          child: Row(
            children: [
              DownloadCover(state: state),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                    if (state.author != null)
                      Text(
                        state.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
