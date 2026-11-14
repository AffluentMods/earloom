// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/cover_surfaces.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/html_text.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../player/player_controller.dart';
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';
import '../data/podcast_repository.dart' show serverMessage;
import 'admin_actions.dart';
import 'episode_widgets.dart';
import 'show_settings_sheet.dart';

/// A podcast show, themed with its cover: header, Play latest and Play all
/// unplayed, then the episodes with sort, filters and seasons. Renders from
/// the cache and refreshes in the background.
class ShowScreen extends ConsumerStatefulWidget {
  const ShowScreen({super.key, required this.show, this.heroTag});

  /// The podcast item (no episode id).
  final ItemRef show;
  final Object? heroTag;

  @override
  ConsumerState<ShowScreen> createState() => _ShowScreenState();
}

class _ShowScreenState extends ConsumerState<ShowScreen> with RefreshingState {
  EpisodeSort? _sort;
  EpisodeFilter _filter = EpisodeFilter.all;

  /// The first refresh ended: a show still missing then is really gone.
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = ref.read(podcastRepositoryProvider);
    if (repository != null && repository.source == widget.show.source) {
      await runRefresh(() => repository.refreshShow(widget.show.itemId, force: force));
    }
    if (mounted && !_refreshed) setState(() => _refreshed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(showDetailProvider(widget.show));
    return detail.when(
      skipLoadingOnReload: true,
      loading: () => const _Loading(),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: ErrorNotice(message: l10n.genericSomethingWentWrong, details: '$e'),
        ),
      ),
      data: (show) {
        if (show == null && !_refreshed) return const _Loading();
        if (show == null && refreshError != null && serverMessage(refreshError!) == null) {
          // Offline, before this show was ever loaded.
          return Scaffold(
            appBar: AppBar(),
            body: RefreshNotice(error: refreshError, padding: const EdgeInsets.all(Space.lg)),
          );
        }
        if (show == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(icon: Icons.podcasts_rounded, title: l10n.itemNotFound, body: l10n.itemNotFoundBody),
          );
        }
        final sort = _sort ?? (show.isSerial ? EpisodeSort.oldest : EpisodeSort.newest);
        return BookCoverTheme(
          book: show.show,
          child: _ShowBody(
            detail: show,
            heroTag: widget.heroTag ?? coverHeroTag(widget.show, 'show'),
            sort: sort,
            filter: _filter,
            onSort: (s) => setState(() => _sort = s),
            onFilter: (f) => setState(() => _filter = f),
            refreshError: refreshError,
            onRefresh: () => _refresh(force: true),
          ),
        );
      },
    );
  }
}

class _ShowBody extends ConsumerWidget {
  const _ShowBody({
    required this.detail,
    required this.heroTag,
    required this.sort,
    required this.filter,
    required this.onSort,
    required this.onFilter,
    required this.refreshError,
    required this.onRefresh,
  });

  final ShowDetail detail;
  final Object heroTag;
  final EpisodeSort sort;
  final EpisodeFilter filter;
  final ValueChanged<EpisodeSort> onSort;
  final ValueChanged<EpisodeFilter> onFilter;
  final Object? refreshError;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showRef = ItemRef(detail.show.ref.source, detail.show.ref.itemId);
    final all = ref.watch(showEpisodesProvider(showRef));
    final episodes = all.value;
    final downloaded = ref.watch(downloadedEpisodesProvider(showRef));
    final access = ref.watch(userAccessProvider).value;
    final admin = access != null && (access.isAdmin || access.canUpdate);
    final shown = episodes == null
        ? null
        : arrangeEpisodes(episodes, sort: sort, filter: filter, downloaded: downloaded);
    final seasons = shown == null ? null : groupBySeason(shown);
    final entries = <Object>[
      if (seasons != null)
        for (final (season, list) in seasons) ...[season, ...list]
      else
        ...?shown,
    ];
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: l10n.podcastSettingsTitle,
            onPressed: () => showShowSettings(context, showRef, title: detail.show.title),
          ),
          if (admin)
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: l10n.podcastAdminActions,
              onPressed: () => showShowAdminActions(context, ref, detail, access),
            ),
        ],
      ),
      body: AnimatedContainer(
        duration: Motion.normal,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.heroTint, scheme.surface],
            stops: const [0, 0.45],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top + kToolbarHeight)),
              SliverToBoxAdapter(
                child: RefreshNotice(
                  error: refreshError,
                  padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
                ),
              ),
              SliverToBoxAdapter(
                child: _Header(detail: detail, heroTag: heroTag, coverSize: (width * 0.52).clamp(160.0, 240.0)),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
                  child: _PlayButtons(episodes: episodes ?? const [], sort: sort),
                ),
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: l10n.podcastEpisodesTitle,
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.sm, 0),
                  action: _SortButton(sort: sort, onSort: onSort),
                ),
              ),
              SliverToBoxAdapter(
                child: _Filters(filter: filter, onFilter: onFilter),
              ),
              if (shown == null)
                const SliverToBoxAdapter(child: _EpisodeSkeleton())
              else if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: filter == EpisodeFilter.all
                      ? EmptyState(
                          icon: Icons.podcasts_rounded,
                          title: refreshError == null ? l10n.podcastNoEpisodes : l10n.podcastNoEpisodesOffline,
                        )
                      : EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: l10n.podcastNoEpisodesFiltered,
                          action: OutlinedButton(
                            onPressed: () => onFilter(EpisodeFilter.all),
                            child: Text(l10n.podcastFilterAll),
                          ),
                        ),
                )
              else
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    if (entry is String) {
                      return SectionHeader(
                        title: entry.isEmpty ? l10n.podcastNoSeason : l10n.podcastSeason(entry),
                        padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.xs),
                      );
                    }
                    final e = entry as EpisodeSummary;
                    return EpisodeRow(key: ValueKey(e.episodeId), episode: e, onShow: true);
                  },
                ),
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xxl)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.heroTag, required this.coverSize});

  final ShowDetail detail;
  final Object heroTag;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final show = detail.show;
    final counts = [
      if (detail.summary.episodeCount > 0) l10n.podcastEpisodes(detail.summary.episodeCount),
      if (detail.summary.episodeCount > 0) l10n.podcastUnplayed(detail.summary.unplayed),
    ].join(' · ');
    final author = detail.author ?? (show.authors.isEmpty ? null : show.authorLine);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        children: [
          Center(
            child: BookCover(book: show, size: coverSize, heroTag: heroTag, showProgress: false),
          ),
          const SizedBox(height: Space.xl),
          Semantics(
            header: true,
            child: Text(
              show.title,
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
          if (author != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              author,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: scheme.onSurface),
            ),
          ],
          if (counts.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              counts,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (detail.descriptionHtml != null && detail.descriptionHtml!.trim().isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: DescriptionText(html: detail.descriptionHtml!, maxLines: 3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Play latest (or resume it), and Play all unplayed, which plays the first
/// and puts the rest at the front of Up next in the list's order.
class _PlayButtons extends ConsumerWidget {
  const _PlayButtons({required this.episodes, required this.sort});

  final List<EpisodeSummary> episodes;
  final EpisodeSort sort;

  /// Up next stays a list a person can scroll: at most this many.
  static const maxQueued = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final latest = arrangeEpisodes(episodes).firstOrNull;
    final unplayed = arrangeEpisodes(episodes, sort: sort, filter: EpisodeFilter.unplayed);
    final playingLatest = ref.watch(
      playerProvider.select((s) => latest != null && s.now?.ref == latest.ref && s.playing),
    );
    // Stacked: both labels stay whole on a small phone and at large text.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: latest == null
              ? null
              : () => playingLatest ? BookActions.playOrPause(ref, latest.ref) : BookActions.play(ref, latest.ref),
          icon: Icon(playingLatest ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
          label: Text(
            playingLatest ? l10n.itemPause : l10n.podcastPlayLatest,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: Space.sm),
        FilledButton.tonalIcon(
          onPressed: unplayed.isEmpty ? null : () => _playAll(context, ref, unplayed),
          icon: const Icon(Icons.playlist_play_rounded, size: 26),
          label: Text(l10n.podcastPlayAllUnplayed, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Future<void> _playAll(BuildContext context, WidgetRef ref, List<EpisodeSummary> unplayed) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(podcastRepositoryProvider);
    if (repository == null) return;
    final engine = ref.read(playerEngineProvider);
    final headers = ref.read(coverHeadersProvider).value ?? const {};
    unawaited(HapticFeedback.lightImpact());
    final rest = unplayed.skip(1).take(maxQueued).toList();
    // In reverse, so they end up at the front in the list's order.
    for (final e in rest.reversed) {
      await engine.playNext(episodeQueueEntry(repository, e, headers));
    }
    await engine.playItem(unplayed.first.ref);
    if (context.mounted && rest.isNotEmpty) showMessage(context, l10n.podcastQueuedUnplayed(rest.length));
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSort});

  final EpisodeSort sort;
  final ValueChanged<EpisodeSort> onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = sort == EpisodeSort.newest ? l10n.podcastSortNewest : l10n.podcastSortOldest;
    return TextButton.icon(
      onPressed: () => onSort(sort == EpisodeSort.newest ? EpisodeSort.oldest : EpisodeSort.newest),
      icon: const Icon(Icons.swap_vert_rounded, size: 20),
      label: Text(label),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onFilter});

  final EpisodeFilter filter;
  final ValueChanged<EpisodeFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      EpisodeFilter.all: l10n.podcastFilterAll,
      EpisodeFilter.unplayed: l10n.podcastFilterUnplayed,
      EpisodeFilter.inProgress: l10n.podcastFilterInProgress,
      EpisodeFilter.downloaded: l10n.podcastFilterDownloaded,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
      child: Row(
        spacing: Space.sm,
        children: [
          for (final MapEntry(key: f, value: label) in labels.entries)
            ChoiceChip(label: Text(label), selected: f == filter, onSelected: (_) => onFilter(f)),
        ],
      ),
    );
  }
}

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 10),
                        SizedBox(height: Space.sm),
                        SkeletonBox(height: 16),
                        SizedBox(height: Space.sm),
                        SkeletonBox(width: 80, height: 10),
                      ],
                    ),
                  ),
                  SizedBox(width: Space.lg),
                  SkeletonBox(width: 44, height: 44, radius: 22),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Column(
            children: [
              SkeletonBox(width: 200, height: 200, radius: Radii.cover),
              SizedBox(height: Space.xl),
              SkeletonBox(width: 240, height: 24),
              SizedBox(height: Space.sm),
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: Space.xl),
              SkeletonBox(height: 52, radius: Radii.pill),
            ],
          ),
        ),
      ),
    );
  }
}
