// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../downloads/data/download_manager.dart';
import '../../downloads/data/offline_providers.dart';
import '../../downloads/ui/download_button.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/progress_badge.dart';
import '../../player/player_controller.dart';
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';
import 'episode_sheet.dart';

/// "Mar 3, 2026", or null when the episode has no date.
String? episodeDate(AppLocalizations l10n, EpisodeSummary e) {
  final date = e.publishedAt ?? (e.sortDate.millisecondsSinceEpoch > 0 ? e.sortDate : null);
  return date == null ? null : DateFormat.yMMMd(l10n.localeName).format(date);
}

/// "Season 2, Episode 5", "Trailer", or null.
String? episodeNumbering(AppLocalizations l10n, EpisodeSummary e) {
  final parts = [
    if (e.season != null) l10n.podcastSeason(e.season!),
    if (e.episodeNumber != null) l10n.podcastEpisodeNumber(e.episodeNumber!),
    if (e.episodeType == 'trailer') l10n.episodeTrailer,
    if (e.episodeType == 'bonus') l10n.episodeBonus,
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// The length, or the time left once started, or "Played".
String? episodeLength(AppLocalizations l10n, EpisodeSummary e) {
  if (e.isPlayed) return l10n.podcastPlayed;
  final p = e.progress;
  if (p != null && e.isInProgress) return formatTimeLeft(l10n, p.remaining);
  return e.duration > Duration.zero ? formatDurationShort(l10n, e.duration) : null;
}

/// What a screen reader says for an episode row.
String episodeSemantics(AppLocalizations l10n, EpisodeSummary e, {bool withShow = false}) => [
  e.title,
  if (withShow) e.showTitle,
  ?episodeDate(l10n, e),
  ?episodeLength(l10n, e),
].join(', ');

/// What the episode actions do, shared by rows, swipes and the sheet.
abstract final class EpisodeActions {
  static Future<void> setPlayed(BuildContext context, WidgetRef ref, EpisodeSummary e, bool played) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(podcastRepositoryProvider);
    if (repository == null || repository.source != e.ref.source) return;
    try {
      await repository.setPlayed(e.ref, played: played);
      unawaited(HapticFeedback.mediumImpact());
      if (context.mounted) showMessage(context, played ? l10n.podcastMarkedPlayed : l10n.podcastMarkedUnplayed);
    } on Object catch (error) {
      if (context.mounted) showActionError(context, error);
    }
  }

  static Future<void> addToQueue(BuildContext context, WidgetRef ref, EpisodeSummary e) =>
      BookActions.addToUpNext(context, ref, e.asBook);

  static Future<void> playNext(BuildContext context, WidgetRef ref, EpisodeSummary e) =>
      BookActions.playNext(context, ref, e.asBook);

  /// Download when not on the phone, remove (after asking) when it is,
  /// else the download's own options.
  static Future<void> toggleDownload(BuildContext context, WidgetRef ref, EpisodeSummary e) async {
    final state = ref.read(downloadStateProvider(e.ref));
    final manager = ref.read(downloadManagerProvider);
    switch (state.phase) {
      case DownloadPhase.none:
        final messenger = ScaffoldMessenger.maybeOf(context);
        final text = AppLocalizations.of(context).downloadQueuedSnack;
        await manager.enqueueItem(e.ref, title: e.title);
        messenger?.showSnackBar(SnackBar(content: Text(text)));
      case DownloadPhase.complete:
        if (await confirmRemoveDownloads(context, count: 1)) await manager.delete(state.key);
      default:
        if (context.mounted) await showDownloadOptions(context, ref, state, title: e.title);
    }
  }

  /// Plays the episode, or pauses it when it is the one playing.
  static Future<void> playOrPause(WidgetRef ref, EpisodeSummary e) => BookActions.playOrPause(ref, e.ref);
}

/// A round play button with the episode's progress as a ring around it.
class EpisodePlayButton extends ConsumerWidget {
  const EpisodePlayButton({super.key, required this.episode, this.size = 44});

  final EpisodeSummary episode;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final playing = ref.watch(playerProvider.select((s) => s.now?.ref == episode.ref && s.playing));
    final live = ref.watch(
      playerProvider.select((s) => s.now?.ref == episode.ref && s.duration > Duration.zero ? s.position : null),
    );
    final p = episode.progress;
    final duration = p != null && p.duration > Duration.zero ? p.duration : episode.duration;
    final fraction = episode.isPlayed
        ? 1.0
        : live != null && duration > Duration.zero
        ? (live.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : (p?.fraction ?? 0.0);
    return Semantics(
      button: true,
      label: playing ? l10n.itemPause : l10n.itemPlay,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => EpisodeActions.playOrPause(ref, episode),
        radius: size / 2 + 4,
        child: SizedBox.square(
          dimension: math.max(size, 48),
          child: Center(
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _Ring(
                  value: fraction,
                  track: scheme.onSurface.withValues(alpha: 0.14),
                  color: scheme.primary,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                      size: size * 0.55,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.max(value, 0.04) * math.pi * 2, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_Ring old) => old.value != value || old.track != track || old.color != color;
}

/// One episode in a list: date and numbering, title, length or time left,
/// download state and a play button with the progress ring. Tap opens the
/// episode sheet; swipe reveals Played, Download and Up next (also offered
/// to screen readers as actions).
class EpisodeRow extends ConsumerStatefulWidget {
  const EpisodeRow({super.key, required this.episode, this.showCover = false, this.onShow = false});

  final EpisodeSummary episode;

  /// The row sits on its show's screen: the sheet offers no way "back" to
  /// the show.
  final bool onShow;

  /// With the show's cover and name, for lists across shows.
  final bool showCover;

  @override
  ConsumerState<EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends ConsumerState<EpisodeRow> with SingleTickerProviderStateMixin {
  static const _actionWidth = 76.0;
  static const _actions = 3;
  late final AnimationController _reveal = AnimationController(vsync: this, duration: Motion.normal);

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  double get _open => _actionWidth * _actions;

  void _drag(DragUpdateDetails d) {
    final dx = Directionality.of(context) == TextDirection.rtl ? -d.primaryDelta! : d.primaryDelta!;
    _reveal.value = (_reveal.value - dx / _open).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (velocity.abs() > 300) {
      velocity < 0 ? _reveal.forward() : _reveal.reverse();
    } else {
      _reveal.value > 0.4 ? _reveal.forward() : _reveal.reverse();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    unawaited(_reveal.reverse());
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final download = ref.watch(downloadStateProvider(e.ref));
    final played = e.isPlayed;
    final downloaded = download.isComplete;
    final current = ref.watch(playerProvider.select((s) => s.now?.ref == e.ref));
    final top = [?episodeDate(l10n, e), ?episodeNumbering(l10n, e)].join(' · ');
    final bottom = [if (widget.showCover) e.showTitle, ?episodeLength(l10n, e)].join(' · ');
    final playedLabel = played ? l10n.podcastMarkUnplayed : l10n.podcastMarkPlayed;
    final downloadLabel = downloaded ? l10n.downloadDelete : l10n.downloadAction;
    final actions = [
      (
        played ? Icons.remove_done_rounded : Icons.done_all_rounded,
        playedLabel,
        () => EpisodeActions.setPlayed(context, ref, e, !played),
      ),
      (
        downloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
        downloadLabel,
        () => EpisodeActions.toggleDownload(context, ref, e),
      ),
      (Icons.playlist_add_rounded, l10n.queueAdd, () => EpisodeActions.addToQueue(context, ref, e)),
    ];
    final row = Material(
      color: current ? scheme.secondaryContainer : scheme.surface,
      child: InkWell(
        onTap: () => showEpisodeSheet(context, e.ref, fromShow: widget.onShow),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
            child: Row(
              children: [
                if (widget.showCover) ...[
                  BookCover(book: e.coverBook, size: 56, shadow: false, showProgress: false),
                  const SizedBox(width: Space.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (top.isNotEmpty)
                        Text(
                          top,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: played ? scheme.onSurfaceVariant : scheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      if (bottom.isNotEmpty) ...[
                        const SizedBox(height: Space.xs),
                        Row(
                          children: [
                            if (played) ...[
                              Icon(Icons.check_circle_rounded, size: 16, color: scheme.primary),
                              const SizedBox(width: Space.xs),
                            ],
                            if (downloaded) ...[
                              Icon(Icons.download_done_rounded, size: 16, color: scheme.primary),
                              const SizedBox(width: Space.xs),
                            ],
                            Flexible(
                              child: Text(
                                bottom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (e.isInProgress) ...[
                        const SizedBox(height: Space.sm),
                        SizedBox(width: 120, child: ThinProgressBar(value: e.progress!.fraction, height: 3)),
                      ],
                    ],
                  ),
                ),
                if (e.ref.source is AbsSource && !downloaded)
                  DownloadButton(itemRef: e.ref, title: e.title, compact: true),
                EpisodePlayButton(episode: e),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: episodeSemantics(l10n, e, withShow: widget.showCover),
      customSemanticsActions: {
        for (final (_, label, run) in actions) CustomSemanticsAction(label: label): () => unawaited(run()),
      },
      child: GestureDetector(
        onHorizontalDragUpdate: _drag,
        onHorizontalDragEnd: _end,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, (icon, label, run)) in actions.indexed)
                        _SwipeAction(
                          width: _actionWidth,
                          icon: icon,
                          label: label,
                          background: i == 0
                              ? scheme.primaryContainer
                              : i == 1
                              ? scheme.secondaryContainer
                              : scheme.tertiaryContainer,
                          foreground: i == 0
                              ? scheme.onPrimaryContainer
                              : i == 1
                              ? scheme.onSecondaryContainer
                              : scheme.onTertiaryContainer,
                          onTap: () => _run(run),
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  final rtl = Directionality.of(context) == TextDirection.rtl;
                  final dx = _reveal.value * _open * (rtl ? 1 : -1);
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: row,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.width,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(height: Space.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An episode on a Home shelf: the show's cover, the episode title, and
/// the show or time left.
class EpisodeCard extends ConsumerWidget {
  const EpisodeCard({super.key, required this.episode, required this.width});

  final EpisodeSummary episode;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final e = episode;
    final second = e.isInProgress ? episodeLength(l10n, e) : e.showTitle;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: episodeSemantics(l10n, e, withShow: true),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => showEpisodeSheet(context, e.ref),
          borderRadius: BorderRadius.circular(coverRadius(width)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              BookCover(book: e.coverBook, size: width),
              const SizedBox(height: Space.sm),
              Flexible(
                child: Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(height: 1.25),
                ),
              ),
              if (second != null) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    second,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A count badge for a show cover: how many episodes are unplayed.
class UnplayedBadge extends StatelessWidget {
  const UnplayedBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.podcastUnplayed(count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: [
            BoxShadow(color: scheme.shadow.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 1)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          NumberFormat.decimalPattern(l10n.localeName).format(count),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
