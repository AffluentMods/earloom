// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/ui/hero_card.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../data/podcast_providers.dart';
import '../data/podcast_repository.dart';
import 'episode_sheet.dart';
import 'episode_widgets.dart';

/// Our own words for the server's podcast shelves; unknown shelves keep
/// the server's label.
String podcastShelfTitle(AppLocalizations l10n, PodcastShelf shelf) => switch (shelf.id) {
  'continue-listening' => l10n.homeContinueListening,
  'newest-episodes' => l10n.homeShelfNewestEpisodes,
  'recently-added' => l10n.homeShelfRecentlyAdded,
  'listen-again' => l10n.homeShelfListenAgain,
  _ => shelf.serverLabel,
};

/// Home when a podcast library is selected (docs/plan/06-phase5-podcasts.md
/// 5.2): the latest episode in progress as the hero, the server's shelves
/// (episodes and shows), then the latest episodes of the library. A sliver
/// for the Home scroll view.
class PodcastHome extends ConsumerStatefulWidget {
  const PodcastHome({super.key, required this.library});

  final LibraryInfo library;

  @override
  ConsumerState<PodcastHome> createState() => _PodcastHomeState();
}

class _PodcastHomeState extends ConsumerState<PodcastHome> {
  static const _collapsedLatest = 8;
  bool _allLatest = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final key = libraryKeyOf(widget.library);
    final inProgress = ref.watch(episodesInProgressProvider(key)).value;
    final shelves = ref.watch(podcastShelvesProvider(key)).value;
    final latest = ref.watch(recentEpisodesProvider(key)).value ?? const [];
    final hero = inProgress?.firstOrNull;
    if (shelves == null || inProgress == null) {
      return const SliverToBoxAdapter(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: SkeletonBox(height: 196, radius: Radii.card),
            ),
            ShelfSkeleton(),
          ],
        ),
      );
    }
    final shown = [
      for (final s in shelves)
        if (s.id == 'continue-listening')
          PodcastShelf(
            id: s.id,
            serverLabel: s.serverLabel,
            episodes: s.episodes.where((e) => e.ref != hero?.ref).toList(),
          )
        else
          s,
    ].where((s) => !s.isEmpty).toList();
    final latestShown = _allLatest ? latest : latest.take(_collapsedLatest).toList();
    if (hero == null && shown.isEmpty && latest.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xxl),
          child: EmptyState(
            icon: Icons.podcasts_rounded,
            title: l10n.podcastHomeEmpty,
            body: l10n.podcastHomeEmptyBody,
          ),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: hero == null
                ? _NothingPlaying(text: l10n.podcastHomeNothingInProgress)
                : HeroCard(book: hero.asBook, cover: hero.coverBook, onOpen: () => showEpisodeSheet(context, hero.ref)),
          ),
        ),
        for (final shelf in shown)
          SliverToBoxAdapter(
            child: shelf.episodes.isNotEmpty
                ? Shelf(
                    title: podcastShelfTitle(l10n, shelf),
                    height: 136 + 72,
                    itemCount: shelf.episodes.length,
                    itemBuilder: (_, i) => EpisodeCard(episode: shelf.episodes[i], width: 136),
                  )
                : Shelf(
                    title: podcastShelfTitle(l10n, shelf),
                    height: 136 + 72,
                    itemCount: shelf.shows.length,
                    itemBuilder: (_, i) => BookGridCard(book: shelf.shows[i], width: 136, place: 'home-${shelf.id}'),
                  ),
          ),
        if (latest.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(title: l10n.podcastLatestEpisodes)),
          SliverList.builder(
            itemCount: latestShown.length,
            itemBuilder: (_, i) =>
                EpisodeRow(key: ValueKey(latestShown[i].ref), episode: latestShown[i], showCover: true),
          ),
          if (latest.length > _collapsedLatest)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _allLatest = !_allLatest),
                    child: Text(_allLatest ? l10n.podcastShowFewer : l10n.podcastShowMore(latest.length)),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(
        children: [
          Icon(Icons.podcasts_rounded, color: scheme.onSurfaceVariant, size: 32),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Refreshes what the podcast Home shows, then quietly the library and
/// every show (at most every few hours) so episode lists work offline and
/// new episodes are found.
Future<void> refreshPodcastHome(WidgetRef ref, LibraryInfo library, {bool force = false}) async {
  final podcasts = currentPodcasts(ref, library.source);
  final books = ref.read(absLibraryRepositoryProvider);
  if (podcasts == null || books == null || books.source != library.source) return;
  await podcasts.refreshHome(library.id, force: force);
  await books.syncLibrary(library.id, force: force);
  unawaited(podcasts.syncShows(library.id).catchError((Object _) {}));
}

/// The podcast repository when [source] is the current account, for
/// widgets.
AbsPodcastRepository? currentPodcasts(WidgetRef ref, Object source) {
  final repository = ref.read(podcastRepositoryProvider);
  return repository != null && repository.source == source ? repository : null;
}
