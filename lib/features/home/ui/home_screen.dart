// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/adaptive.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/library_switcher.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../library/ui/widgets/progress_badge.dart';
import '../../player/player_controller.dart';
import '../../podcasts/ui/podcast_home.dart';
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
    if (library.isPodcast) return refreshPodcastHome(ref, library, force: force);
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
              // Lines the title up with the cards under it.
              titleSpacing: context.gutter - Space.sm,
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
            else if (library.isPodcast && library.source is AbsSource)
              PodcastHome(key: ValueKey(library.id), library: library)
            else ...[
              if (continuing.isNotEmpty)
                SliverToBoxAdapter(child: _ContinueListening(books: continuing))
              else
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
          padding: EdgeInsets.fromLTRB(context.gutter, Space.xl, context.gutter, 0),
          // Full width on a phone; a normal button, not a bar, on a tablet.
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ContentWidth.form),
              child: OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.importFiles),
                icon: const Icon(Icons.library_add_outlined),
                label: Text(l10n.homeAddFiles),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
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
            height: cardShelfHeight(context, shelfCoverWidth(context)),
            itemCount: shelf.series.length,
            itemBuilder: (_, j) => SeriesCard(series: shelf.series[j], width: shelfCoverWidth(context)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (books.isEmpty) return const SizedBox.shrink();
    final width = shelfCoverWidth(context);
    return Shelf(
      title: title,
      action: action,
      height: cardShelfHeight(context, width),
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

/// The book to go back to, and the other books in progress. Phones get the
/// hero card and a shelf under it. Tablets get the wide hero card, and on
/// wide screens the other books sit in a panel beside it, as tall as the
/// card.
class _ContinueListening extends StatelessWidget {
  const _ContinueListening({required this.books});

  final List<BookSummary> books;

  /// Content width from which the others move into a side panel.
  static const _panelFrom = 900.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = context.gutter;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth - 2 * gutter >= ContentWidth.form;
        final others = books.skip(1).toList();
        final panel = others.isNotEmpty && box.maxWidth >= _panelFrom;
        final hero = HeroCard(book: books.first, wide: wide);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, Space.sm, gutter, 0),
              child: panel
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: hero),
                          const SizedBox(width: Space.lg),
                          Expanded(
                            flex: 2,
                            child: NoIntrinsicHeight(child: _InProgressPanel(books: others)),
                          ),
                        ],
                      ),
                    )
                  : hero,
            ),
            if (!panel && others.isNotEmpty)
              _BookShelf(title: l10n.homeShelfAlsoInProgress, books: others, place: 'home-continue'),
          ],
        );
      },
    );
  }
}

/// Other books in progress, beside the hero card on wide screens: a short
/// scrolling list with a Resume button on each.
class _InProgressPanel extends StatelessWidget {
  const _InProgressPanel({required this.books});

  final List<BookSummary> books;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xs),
            child: Semantics(
              header: true,
              child: Text(l10n.homeShelfAlsoInProgress, style: theme.textTheme.sectionTitle),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: Space.sm),
              itemCount: books.length,
              itemBuilder: (context, i) => _InProgressRow(book: books[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InProgressRow extends ConsumerWidget {
  const _InProgressRow({required this.book});

  final BookSummary book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tag = coverHeroTag(book.ref, 'home-panel');
    final progress = book.progress;
    final details = [
      if (book.authors.isNotEmpty) book.authorLine,
      if (progress != null && progress.duration > Duration.zero) formatTimeLeft(l10n, progress.remaining),
    ].join(' · ');
    final isCurrent = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref));
    final playing = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref && s.playing));
    return InkWell(
      onTap: () => BrowseNav.open(context, book, heroTag: tag),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: bookSemantics(l10n, book),
                excludeSemantics: true,
                child: Row(
                  children: [
                    BookCover(book: book, size: 52, heroTag: tag, showProgress: false),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          if (details.isNotEmpty)
                            Text(
                              details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          if (progress != null) ...[
                            const SizedBox(height: Space.sm),
                            ThinProgressBar(value: progress.fraction, height: 3),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              tooltip: playing ? l10n.homePause : l10n.homeResume,
              onPressed: () => isCurrent ? BookActions.playOrPause(ref, book.ref) : BookActions.play(ref, book.ref),
            ),
          ],
        ),
      ),
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
      padding: EdgeInsets.fromLTRB(context.gutter, Space.sm, context.gutter, 0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: ContentWidth.reading),
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
    // A phone-width column in the middle on tablets: buttons stretched
    // across a whole tablet read as bars, not buttons.
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ContentWidth.form),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.gutter, Space.sm, context.gutter, 0),
          child: SkeletonBox(height: context.windowSize.atLeast(WindowSize.medium) ? 232 : 196, radius: Radii.card),
        ),
        const ShelfSkeleton(),
        const ShelfSkeleton(),
      ],
    );
  }
}
