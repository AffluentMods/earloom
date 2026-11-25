// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/library_switcher.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';
import 'add_podcast_screen.dart';
import 'episode_widgets.dart';
import 'podcast_home.dart';

/// The Podcasts tab of the Library: the shows of the server's podcast
/// library (the selected one when there are several), and the authors and
/// series the user moved here from a book library.
class PodcastsTab extends ConsumerWidget {
  const PodcastsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(podcastsLibraryProvider);
    // A new library starts with its own sort and scroll position.
    return PodcastShowsView(key: ValueKey(library == null ? '' : selectionKey(library)), library: library);
  }
}

/// The shows of one podcast library as a grid, each with how many episodes
/// are unplayed, sorted by title, recent episodes or when they were added.
/// The authors and series moved to Podcasts are cards among them. Admins
/// can add a show here.
class PodcastShowsView extends ConsumerStatefulWidget {
  const PodcastShowsView({super.key, required this.library});

  /// Null when the server has no podcast library: then only the moved
  /// authors and series show.
  final LibraryInfo? library;

  @override
  ConsumerState<PodcastShowsView> createState() => _PodcastShowsViewState();
}

class _PodcastShowsViewState extends ConsumerState<PodcastShowsView>
    with RefreshingState, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  ShowSort _sort = ShowSort.title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync({bool force = false}) => runRefresh(() async {
    final books = ref.read(absLibraryRepositoryProvider);
    if (books == null) return;
    final library = widget.library;
    final podcasts = library == null ? null : currentPodcasts(ref, library.source);
    if (library != null && podcasts != null && books.source == library.source) {
      await books.syncLibrary(library.id, force: force);
      // Every show's episodes, quietly and at most every few hours.
      unawaited(podcasts.syncShows(library.id).catchError((Object _) {}));
    }
    // The books of the moved authors and series, also new ones.
    final moved = ref.read(podcastGroupsOfAccountProvider);
    for (final libraryId in {for (final g in moved) g.libraryId}) {
      await books.syncLibrary(libraryId, force: force);
    }
    for (final g in moved) {
      if (g.kind == BookGroupKind.series) await books.refreshSeries(g.id, force: force);
    }
    if (force) await books.refreshProgress();
  });

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final labels = {
      ShowSort.title: l10n.librarySortTitle,
      ShowSort.recentlyUpdated: l10n.podcastSortUpdated,
      ShowSort.addedAt: l10n.librarySortAdded,
    };
    final picked = await showModalBottomSheet<ShowSort>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.sm),
              child: Text(l10n.librarySort, style: Theme.of(sheet).textTheme.titleLarge),
            ),
            RadioGroup<ShowSort>(
              groupValue: _sort,
              onChanged: (v) => Navigator.pop(sheet, v),
              child: Column(
                children: [
                  for (final MapEntry(key: sort, value: label) in labels.entries)
                    RadioListTile<ShowSort>(value: sort, title: Text(label)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final libraries = ref.watch(podcastLibrariesProvider);
    final sortLabel = switch (_sort) {
      ShowSort.title => l10n.librarySortTitle,
      ShowSort.recentlyUpdated => l10n.podcastSortUpdated,
      ShowSort.addedAt => l10n.librarySortAdded,
    };
    final library = widget.library;
    final shows = library == null
        ? const AsyncData(<ShowSummary>[])
        : ref.watch(podcastShowsProvider((source: library.source, libraryId: library.id, sort: _sort)));
    final groups = ref.watch(podcastGroupsProvider);
    final admin = library != null && (ref.watch(userAccessProvider).value?.isAdmin ?? false);
    final list = shows.hasValue && groups.hasValue ? podcastsGrid(shows.value!, groups.value!, _sort) : null;
    Widget body;
    if (list == null) {
      body = const SliverGridSkeleton();
    } else if (list.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.podcasts_rounded,
          title: l10n.podcastLibraryEmpty,
          action: admin
              ? FilledButton.icon(
                  onPressed: () => openAddPodcast(context, library.id),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.podcastAdminAdd),
                )
              : null,
        ),
      );
    } else {
      body = SliverPadding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
        sliver: SliverGrid.builder(
          gridDelegate: bookGridDelegate(context),
          itemCount: list.length,
          itemBuilder: (context, i) => LayoutBuilder(
            builder: (context, c) => switch (list[i]) {
              PodcastsShowCard(:final show) => _ShowCard(show: show, width: c.maxWidth),
              PodcastsGroupCard(:final group) => _GroupCard(group: group, width: c.maxWidth),
            },
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _sync(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
          // Sort, the library when there are several, and Add for admins.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (library != null && libraries.length > 1)
                    LibrarySwitcherButton(library: library, only: (l) => l.isPodcast),
                  ActionChip(
                    side: BorderSide(color: scheme.outline),
                    avatar: const Icon(Icons.swap_vert_rounded),
                    label: Text(sortLabel),
                    tooltip: l10n.librarySort,
                    onPressed: _pickSort,
                  ),
                  if (admin)
                    ActionChip(
                      side: BorderSide(color: scheme.outline),
                      avatar: const Icon(Icons.add_rounded),
                      label: Text(l10n.podcastAdminAdd),
                      onPressed: () => openAddPodcast(context, library.id),
                    ),
                ],
              ),
            ),
          ),
          body,
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xl)),
        ],
      ),
    );
  }
}

/// A show in the grid, with its unplayed count on the cover.
class _ShowCard extends StatelessWidget {
  const _ShowCard({required this.show, required this.width});

  final ShowSummary show;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        BookGridCard(book: show.show, width: width, place: 'podcasts'),
        if (show.unplayed > 0)
          Positioned(
            top: Space.sm,
            right: Space.sm,
            child: UnplayedBadge(count: show.unplayed),
          ),
      ],
    );
  }
}

/// An author or a series moved here, laid out like a show: its newest
/// covers, how many books ("episodes") and how many are not finished.
/// Opens the author or the series.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.width});

  final PodcastsGroup group;
  final double width;

  @override
  Widget build(BuildContext context) {
    final entry = group.entry;
    return Stack(
      children: [
        BookGroupCard(
          group: entry.group,
          books: entry.books,
          count: entry.count,
          width: width,
          line: AppLocalizations.of(context).groupCardEpisodes(entry.count),
        ),
        if (group.unplayed > 0)
          Positioned(
            top: Space.sm,
            right: Space.sm,
            child: UnplayedBadge(count: group.unplayed),
          ),
      ],
    );
  }
}
