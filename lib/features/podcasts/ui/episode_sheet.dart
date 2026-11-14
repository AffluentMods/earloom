// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/cover_surfaces.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/html_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../downloads/ui/download_button.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../library/ui/widgets/progress_badge.dart';
import '../../player/player_controller.dart';
import '../../player/ui/player_widgets.dart' show formatClock;
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';
import 'episode_widgets.dart';

/// Opens the episode sheet for [episode] (a podcast item plus episode id).
/// [fromShow] hides "Go to show" when the show is what is underneath.
Future<void> showEpisodeSheet(BuildContext context, ItemRef episode, {bool fromShow = false}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scroll) => EpisodeSheet(
        episode: episode,
        controller: scroll,
        onOpenShow: fromShow
            ? null
            : () {
                Navigator.pop(sheet);
                BrowseNav.show(context, ItemRef(episode.source, episode.itemId));
              },
      ),
    ),
  );
}

/// One episode: title, date, length, the actions (play, download, Up
/// next, played), progress, chapters and the show notes. Times in the show
/// notes play the episode from there, also when it is not playing yet.
class EpisodeSheet extends ConsumerStatefulWidget {
  const EpisodeSheet({super.key, required this.episode, this.controller, this.onOpenShow});

  final ItemRef episode;
  final ScrollController? controller;
  final VoidCallback? onOpenShow;

  @override
  ConsumerState<EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends ConsumerState<EpisodeSheet> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchIfMissing());
  }

  /// An episode from a notification or a link may not be cached yet.
  Future<void> _fetchIfMissing() async {
    final repository = ref.read(podcastRepositoryProvider);
    if (repository == null || repository.source != widget.episode.source) return;
    final cached = await ref.read(episodeProvider(widget.episode).future);
    if (cached == null) await runRefresh(() => repository.refreshEpisode(widget.episode));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(episodeProvider(widget.episode));
    final e = value.value;
    if (e == null) {
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.all(Space.xl),
        children: [
          if (value.isLoading || refreshError == null && !value.hasError)
            const ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 240, height: 24),
                  SizedBox(height: Space.md),
                  SkeletonBox(width: 160, height: 16),
                  SizedBox(height: Space.xl),
                  SkeletonBox(height: 52, radius: Radii.pill),
                ],
              ),
            )
          else
            ErrorNotice(
              message: l10n.podcastEpisodeNotFound,
              details: refreshError == null ? null : failureDetails(refreshError!),
            ),
        ],
      );
    }
    return BookCoverTheme(
      book: e.asBook,
      child: _Body(episode: e, controller: widget.controller, onOpenShow: widget.onOpenShow),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.episode, required this.controller, required this.onOpenShow});

  final EpisodeSummary episode;
  final ScrollController? controller;
  final VoidCallback? onOpenShow;

  /// Plays from [at]: a seek when this episode is loaded, else it starts
  /// there.
  Future<void> _playFrom(WidgetRef ref, Duration at) => BookActions.play(ref, episode.ref, startAt: at);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final e = episode;
    final meta = [?episodeDate(l10n, e), ?episodeNumbering(l10n, e)].join(' · ');
    final notes = e.descriptionHtml;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.heroTint, scheme.surfaceContainerLow],
            stops: const [0, 0.4],
          ),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, MediaQuery.paddingOf(context).bottom + Space.xxl),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(book: e.coverBook, size: 72, showProgress: false),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        button: onOpenShow != null,
                        child: InkWell(
                          onTap: onOpenShow,
                          borderRadius: BorderRadius.circular(Space.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.xs),
                            child: Text(
                              e.showTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelLarge?.copyWith(color: scheme.primary),
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        header: true,
                        child: Text(e.title, style: text.titleLarge?.copyWith(color: scheme.onSurface, fontSize: 24)),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: Space.xs),
                        Text(meta, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _PlayButton(episode: e),
            _Progress(episode: e),
            const SizedBox(height: Space.md),
            _ActionRow(episode: e, onOpenShow: onOpenShow),
            if (e.chapters.length > 1) ...[
              SectionHeader(
                title: l10n.itemChapters,
                padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.sm),
                action: Text(
                  l10n.itemChapterCount(e.chapters.length),
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              for (final c in e.chapters)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  title: Text(c.title.isEmpty ? l10n.chapterNumber(c.index + 1) : c.title),
                  trailing: Text(
                    formatClock(c.start),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  onTap: () => _playFrom(ref, c.start),
                ),
            ],
            SectionHeader(title: l10n.podcastShowNotes, padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.sm)),
            if (notes != null && notes.trim().isNotEmpty)
              DescriptionText(
                html: notes,
                maxLines: 400,
                maxPosition: e.duration > Duration.zero ? e.duration : null,
                onTimestamp: (at) => _playFrom(ref, at),
                timestampLabel: l10n.episodePlayFrom,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface, height: 1.5),
              )
            else
              Text(l10n.podcastNoShowNotes, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.episode});

  final EpisodeSummary episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final e = episode;
    final current = ref.watch(playerProvider.select((s) => s.now?.ref == e.ref));
    final playing = ref.watch(playerProvider.select((s) => s.now?.ref == e.ref && s.playing));
    final p = e.progress;
    final (IconData icon, String label, Duration? startAt) = switch (p) {
      _ when playing => (Icons.pause_rounded, l10n.itemPause, null),
      final p? when p.isFinished && !current => (Icons.replay_rounded, l10n.itemListenAgain, Duration.zero),
      final p? when p.isStarted => (
        Icons.play_arrow_rounded,
        l10n.itemActionWithDetail(l10n.itemResume, formatTimeLeft(l10n, p.remaining)),
        null,
      ),
      _ => (
        Icons.play_arrow_rounded,
        e.duration > Duration.zero
            ? l10n.itemActionWithDetail(l10n.itemPlay, formatDurationShort(l10n, e.duration))
            : l10n.itemPlay,
        null,
      ),
    };
    return FilledButton.icon(
      onPressed: () => current ? BookActions.playOrPause(ref, e.ref) : BookActions.play(ref, e.ref, startAt: startAt),
      icon: Icon(icon, size: 28),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    );
  }
}

class _Progress extends ConsumerWidget {
  const _Progress({required this.episode});

  final EpisodeSummary episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final live = ref.watch(playerProvider.select((s) => s.now?.ref == episode.ref ? s.position : null));
    final p = episode.progress;
    final duration = p != null && p.duration > Duration.zero ? p.duration : episode.duration;
    if (duration <= Duration.zero) return const SizedBox.shrink();
    final position = live ?? p?.position ?? Duration.zero;
    if (episode.isPlayed && live == null) return const SizedBox.shrink();
    if (position < const Duration(seconds: 5)) return const SizedBox.shrink();
    final fraction = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThinProgressBar(value: fraction, height: 6),
          const SizedBox(height: Space.sm),
          Text(
            formatTimeLeft(l10n, duration - position),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.episode, required this.onOpenShow});

  final EpisodeSummary episode;
  final VoidCallback? onOpenShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final e = episode;
    final played = e.isPlayed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (e.ref.source is AbsSource)
          Expanded(
            child: Center(
              child: DownloadButton(itemRef: e.ref, title: e.title, compact: true),
            ),
          ),
        Expanded(
          child: _Action(
            icon: played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
            label: l10n.podcastPlayed,
            semanticLabel: played ? l10n.podcastMarkUnplayed : l10n.podcastMarkPlayed,
            selected: played,
            onTap: () => EpisodeActions.setPlayed(context, ref, e, !played),
          ),
        ),
        Expanded(
          child: _Action(
            icon: Icons.queue_rounded,
            label: l10n.queuePlayNext,
            onTap: () => EpisodeActions.playNext(context, ref, e),
          ),
        ),
        Expanded(
          child: _Action(
            icon: Icons.playlist_add_rounded,
            label: l10n.queueAddShort,
            semanticLabel: l10n.queueAdd,
            onTap: () => EpisodeActions.addToQueue(context, ref, e),
          ),
        ),
        if (onOpenShow != null)
          Expanded(
            child: _Action(icon: Icons.podcasts_rounded, label: l10n.podcastGoToShow, onTap: onOpenShow!),
          ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Space.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Icon(icon, key: ValueKey(icon), color: color),
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
