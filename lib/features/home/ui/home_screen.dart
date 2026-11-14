// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/library_switcher.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../data/home_repository.dart';
import 'hero_card.dart';

/// The Home tab: the book to go back to, then shelves. Books from the
/// server and from this phone mix in Continue listening by when they were
/// last played. Renders from the cache, refreshes in the background.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(runRefresh(() => _refreshAccount()));
      // Shelves follow the library selection, now and whenever it changes.
      ref.listenManual(
        currentLibraryProvider.select((l) => l.value?.id),
        (previous, next) {
          if (next != null && previous != next) unawaited(runRefresh(() => _refreshLibrary()));
        },
        fireImmediately: true,
      );
    });
  }

  /// Progress and the library list: what Continue listening and the
  /// switcher need.
  Future<void> _refreshAccount({bool force = false}) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null) return;
    await Future.wait([repository.refreshLibraries(force: force), repository.refreshProgress()]);
  }

  /// Shelves of the selected server library, then a quiet full sync of it
  /// so Library, filters and offline search have everything (at most every
  /// few hours unless pulled).
  Future<void> _refreshLibrary({bool force = false}) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    final library = ref.read(currentLibraryProvider).value;
    if (repository == null || library == null || library.source != repository.source) return;
    await repository.refreshShelves(library.id, force: force);
    await repository.syncLibrary(library.id, force: force);
  }

  Future<void> _refresh({bool force = false}) =>
      runRefresh(() => Future.wait([_refreshAccount(force: force), _refreshLibrary(force: force)]));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(currentLibraryProvider).value;
    final hasAccount = ref.watch(accountSessionProvider) != null;
    final libraries = ref.watch(availableLibrariesProvider).value ?? const [localLibrary];
    final inProgress = ref.watch(continueListeningProvider);
    final localBooks = ref.watch(recentLocalBooksProvider);

    final loading = library == null || !inProgress.hasValue || !localBooks.hasValue;
    final local = localBooks.value ?? const [];
    final continuing = inProgress.value ?? const [];
    final welcome = !loading && !hasAccount && local.isEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              titleSpacing: Space.sm,
              title: library != null && libraries.length > 1
                  ? LibrarySwitcherButton(library: library, large: true)
                  : Padding(
                      padding: const EdgeInsets.only(left: Space.sm),
                      child: Text(l10n.tabHome),
                    ),
            ),
            SliverToBoxAdapter(child: RefreshNotice(error: refreshError)),
            if (loading)
              const SliverToBoxAdapter(child: _HomeSkeleton())
            else if (welcome)
              const SliverFillRemaining(hasScrollBody: false, child: _Welcome())
            else ...[
              if (continuing.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                    child: HeroCard(book: continuing.first),
                  ),
                ),
                if (continuing.length > 1)
                  SliverToBoxAdapter(
                    child: _BookShelf(
                      title: l10n.homeContinueListening,
                      books: continuing.skip(1).toList(),
                      place: 'home-continue',
                    ),
                  ),
              ] else
                SliverToBoxAdapter(child: _NothingInProgress(hasBooks: local.isNotEmpty || hasAccount)),
              if (library.source is AbsSource) _ServerShelves(libraryId: library.id) else ..._localShelves(l10n, local),
              if (library.source is AbsSource && local.isNotEmpty)
                SliverToBoxAdapter(
                  child: _BookShelf(
                    title: l10n.homeShelfOnThisDevice,
                    books: local.take(12).toList(),
                    place: 'home-local',
                    action: TextButton(
                      onPressed: () async {
                        final router = GoRouter.of(context);
                        await selectLibrary(ref.read(globalDbProvider), localLibrary);
                        router.go(AppRoutes.library);
                      },
                      child: Text(l10n.genericSeeAll),
                    ),
                  ),
                ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xxl)),
          ],
        ),
      ),
    );
  }

  /// Home for On this device: newest imports and finished books.
  List<Widget> _localShelves(AppLocalizations l10n, List<BookSummary> local) {
    final finished = local.where((b) => b.progress?.isFinished ?? false).toList();
    return [
      if (local.isNotEmpty)
        SliverToBoxAdapter(
          child: _BookShelf(
            title: l10n.homeShelfRecentlyAdded,
            books: local.take(12).toList(),
            place: 'home-local-new',
          ),
        ),
      if (finished.isNotEmpty)
        SliverToBoxAdapter(
          child: _BookShelf(title: l10n.homeShelfListenAgain, books: finished, place: 'home-local-again'),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, 0),
          child: OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.importFiles),
            icon: const Icon(Icons.library_add_outlined),
            label: Text(l10n.homeAddFiles),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    ];
  }
}

/// The server's personalized shelves for one library, in server order.
/// Continue listening is left out: Home shows its own, mixed with books on
/// this phone.
class _ServerShelves extends ConsumerWidget {
  const _ServerShelves({required this.libraryId});

  final String libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shelves = ref.watch(homeShelvesProvider(libraryId));
    final list = shelves.value;
    if (list == null) return const SliverToBoxAdapter(child: ShelfSkeleton());
    final shown = list.where((s) => s.id != 'continue-listening').toList();
    if (shown.isEmpty) {
      final libraries = ref.watch(absLibrariesProvider).value ?? const [];
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xxl),
          child: EmptyState(
            icon: Icons.auto_stories_outlined,
            title: libraries.isEmpty ? l10n.homeEmptyNoLibraries : l10n.homeEmptyLibrary,
          ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final shelf = shown[i];
        final title = shelfTitle(l10n, shelf);
        return switch (shelf.kind) {
          ShelfKind.books => _BookShelf(
            title: title,
            books: shelf.books,
            place: 'home-${shelf.id}',
            showSeries: shelf.id == 'continue-series',
          ),
          ShelfKind.series => Shelf(
            title: title,
            height: 136 + 72,
            itemCount: shelf.series.length,
            itemBuilder: (_, j) => SeriesCard(series: shelf.series[j], width: 136),
          ),
          ShelfKind.authors => Shelf(
            title: title,
            height: 160,
            spacing: Space.md,
            itemCount: shelf.authors.length,
            itemBuilder: (_, j) => AuthorCard(author: shelf.authors[j], width: 104),
          ),
        };
      },
    );
  }
}

/// Our own words for the server's shelves; unknown shelves keep the
/// server's label.
String shelfTitle(AppLocalizations l10n, HomeShelf shelf) => switch (shelf.id) {
  'continue-listening' => l10n.homeContinueListening,
  'continue-series' => l10n.homeShelfContinueSeries,
  'continue-reading' => l10n.homeShelfContinueReading,
  'recently-added' => l10n.homeShelfRecentlyAdded,
  'recent-series' => l10n.homeShelfRecentSeries,
  'discover' => l10n.homeShelfDiscover,
  'listen-again' => l10n.homeShelfListenAgain,
  'read-again' => l10n.homeShelfReadAgain,
  'newest-authors' => l10n.homeShelfNewestAuthors,
  'newest-episodes' => l10n.homeShelfNewestEpisodes,
  _ => shelf.serverLabel,
};

class _BookShelf extends StatelessWidget {
  const _BookShelf({
    required this.title,
    required this.books,
    required this.place,
    this.action,
    this.showSeries = false,
  });

  final String title;
  final List<BookSummary> books;
  final String place;
  final Widget? action;

  /// Under the cover, "Book 3 of The Example Saga" instead of the author.
  final bool showSeries;

  static const width = 136.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (books.isEmpty) return const SizedBox.shrink();
    return Shelf(
      title: title,
      action: action,
      height: width + 72,
      itemCount: books.length,
      itemBuilder: (_, i) {
        final b = books[i];
        return BookGridCard(
          book: b,
          width: width,
          place: place,
          subtitle: showSeries && b.seriesSequence != null && b.seriesName != null
              ? l10n.itemSeriesPosition(b.seriesSequence!, b.seriesName!)
              : null,
        );
      },
    );
  }
}

class _NothingInProgress extends StatelessWidget {
  const _NothingInProgress({required this.hasBooks});

  final bool hasBooks;

  @override
  Widget build(BuildContext context) {
    if (!hasBooks) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Container(
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Row(
          children: [
            Icon(Icons.headphones_rounded, color: scheme.onSurfaceVariant, size: 32),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Text(
                AppLocalizations.of(context).homeEmptyNothingInProgress,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No server and no imported books yet: the two ways in.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.headphones_rounded, size: 44, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: Space.xl),
          Text(l10n.homeWelcomeTitle, textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: Space.md),
          Text(
            l10n.homeWelcomeBody,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.xxl),
          FilledButton.icon(
            onPressed: () => context.push(AppRoutes.addServer),
            icon: const Icon(Icons.dns_outlined),
            label: Text(l10n.onboardingConnectServer),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.importFiles),
            icon: const Icon(Icons.library_add_outlined),
            label: Text(l10n.homeAddFiles),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
          child: SkeletonBox(height: 196, radius: Radii.card),
        ),
        ShelfSkeleton(),
        ShelfSkeleton(),
      ],
    );
  }
}
