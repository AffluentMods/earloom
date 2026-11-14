// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
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

/// The Library tab for a podcast library: the shows as a grid, each with
/// how many episodes are unplayed, sorted by title, recent episodes or
/// when they were added. Admins can add a show here.
class PodcastLibraryScreen extends ConsumerStatefulWidget {
  const PodcastLibraryScreen({super.key, required this.library});

  final LibraryInfo library;

  @override
  ConsumerState<PodcastLibraryScreen> createState() => _PodcastLibraryScreenState();
}

class _PodcastLibraryScreenState extends ConsumerState<PodcastLibraryScreen> with RefreshingState {
  ShowSort _sort = ShowSort.title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync({bool force = false}) => runRefresh(() async {
    final books = ref.read(absLibraryRepositoryProvider);
    final podcasts = currentPodcasts(ref, widget.library.source);
    if (books == null || podcasts == null || books.source != widget.library.source) return;
    await books.syncLibrary(widget.library.id, force: force);
    if (force) await books.refreshProgress();
    // Every show's episodes, quietly and at most every few hours.
    unawaited(podcasts.syncShows(widget.library.id).catchError((Object _) {}));
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
    final l10n = AppLocalizations.of(context);
    final shows = ref.watch(
      podcastShowsProvider((source: widget.library.source, libraryId: widget.library.id, sort: _sort)),
    );
    final admin = ref.watch(userAccessProvider).value?.isAdmin ?? false;
    final list = shows.value;
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
                  onPressed: () => openAddPodcast(context, widget.library.id),
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
            builder: (context, c) => _ShowCard(show: list[i], width: c.maxWidth),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.sm,
        title: LibrarySwitcherButton(library: widget.library, large: true),
        actions: [
          IconButton(icon: const Icon(Icons.swap_vert_rounded), tooltip: l10n.librarySort, onPressed: _pickSort),
          if (admin)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: l10n.podcastAdminAdd,
              onPressed: () => openAddPodcast(context, widget.library.id),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _sync(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
            body,
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xl)),
          ],
        ),
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
