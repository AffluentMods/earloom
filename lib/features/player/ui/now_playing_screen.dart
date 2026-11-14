// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/cover_surfaces.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../chapters.dart';
import '../player_controller.dart';
import '../sleep_timer.dart';
import 'bookmarks_sheet.dart';
import 'chapters_sheet.dart';
import 'player_settings_sheet.dart';
import 'player_widgets.dart';
import 'queue_sheet.dart';
import 'sleep_sheet.dart';
import 'speed_sheet.dart';

/// The full-screen player, a modal that slides up over the tabs.
class NowPlayingPage extends CustomTransitionPage<void> {
  const NowPlayingPage({super.key})
    : super(
        fullscreenDialog: true,
        opaque: false,
        transitionDuration: Motion.normal,
        reverseTransitionDuration: Motion.normal,
        child: const NowPlayingScreen(),
        transitionsBuilder: _slideUp,
      );

  static Widget _slideUp(BuildContext context, Animation<double> animation, Animation<double> _, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

/// Hero tag shared by the mini player cover and the Now Playing cover.
const nowPlayingCoverTag = 'now-playing-cover';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with SingleTickerProviderStateMixin {
  /// The background drifts through one slow loop: calm, never strobing.
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 28));
  double _drag = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !ref.read(playerProvider).hasBook) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      unawaited(_drift.repeat());
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final hasBook = ref.watch(playerProvider.select((s) => s.hasBook));
    if (!hasBook) {
      // Stopped from the notification while open: nothing to show.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Opened by a link with nothing loaded, or stopped from the
        // notification: go back, or Home when there is nothing to go back to.
        if (Navigator.of(context).canPop()) {
          _close();
        } else {
          context.go(AppRoutes.home);
        }
      });
      return const SizedBox.shrink();
    }
    return NowPlayingTheme(
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final colors = scheme.ambientGradient;
          return GestureDetector(
            // Swipe down anywhere outside the scrubber to close.
            onVerticalDragUpdate: (d) => setState(() => _drag = math.max(0, _drag + d.delta.dy)),
            onVerticalDragEnd: (d) {
              if (_drag > 140 || (d.primaryVelocity ?? 0) > 900) {
                _close();
              } else {
                setState(() => _drag = 0);
              }
            },
            child: AnimatedContainer(
              duration: _drag == 0 ? Motion.fast : Duration.zero,
              transform: Matrix4.translationValues(0, _drag, 0),
              child: Scaffold(
                body: AnimatedBuilder(
                  animation: _drift,
                  builder: (context, child) {
                    final t = _drift.value * 2 * math.pi;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 + 0.35 * math.sin(t), -1 + 0.25 * math.cos(t)),
                          end: Alignment(1 - 0.3 * math.cos(t), 1 - 0.35 * math.sin(t)),
                          colors: colors,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: SafeArea(child: _Body(onClose: _close)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight && box.maxWidth >= Breakpoints.medium;
        final top = _TopBar(onClose: onClose);
        if (wide) {
          return Column(
            children: [
              top,
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(child: _Cover(maxSize: box.maxHeight * 0.75)),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: Space.xl),
                        child: _Controls(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
          child: Column(
            children: [
              top,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) => Center(child: _Cover(maxSize: area.biggest.shortestSide)),
                ),
              ),
              const _Controls(),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(playerProvider.select((s) => s.now));
    final engine = ref.read(playerEngineProvider);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          tooltip: l10n.playerClose,
          onPressed: onClose,
        ),
        Expanded(
          child: Text(
            now?.seriesLine ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        PopupMenuButton<_Menu>(
          icon: const Icon(Icons.more_horiz_rounded),
          tooltip: l10n.playerMore,
          onSelected: (choice) async {
            switch (choice) {
              case _Menu.book:
                final location = bookLocation(ref.read(playerProvider));
                onClose();
                if (location != null) unawaited(GoRouter.of(context).push(location));
              case _Menu.bookmarks:
                await showBookmarksSheet(context);
              case _Menu.queue:
                await showQueueSheet(context);
              case _Menu.settings:
                await showPlayerSettings(context);
              case _Menu.stop:
                onClose();
                await engine.stop();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: _Menu.book, child: _MenuRow(Icons.menu_book_outlined, l10n.playerGoToBook)),
            PopupMenuItem(value: _Menu.bookmarks, child: _MenuRow(Icons.bookmarks_outlined, l10n.playerBookmarks)),
            PopupMenuItem(value: _Menu.queue, child: _MenuRow(Icons.queue_music_rounded, l10n.playerQueue)),
            PopupMenuItem(value: _Menu.settings, child: _MenuRow(Icons.tune_rounded, l10n.playerSettings)),
            PopupMenuItem(value: _Menu.stop, child: _MenuRow(Icons.stop_circle_outlined, l10n.playerStop)),
          ],
        ),
      ],
    );
  }
}

enum _Menu { book, bookmarks, queue, settings, stop }

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: Space.md),
      Flexible(child: Text(label)),
    ],
  );
}

/// The cover: big, rounded, softly shadowed, a little smaller while paused.
class _Cover extends ConsumerWidget {
  const _Cover({required this.maxSize});
  final double maxSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (now, playing) = ref.watch(playerProvider.select((s) => (s.now, s.playing)));
    if (now == null) return const SizedBox.shrink();
    final size = maxSize.clamp(120.0, 420.0) - Space.lg;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: playing || reduceMotion ? 1 : 0.92,
      duration: Motion.slow,
      curve: Curves.easeOutBack,
      child: CoverImage(source: now.cover, title: now.title, size: size, heroTag: nowPlayingCoverTag, shadow: true),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  /// Natural width of the transport row: measured on a 320 point phone.
  static const _controlsWidth = 312.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final now = ref.watch(playerProvider.select((s) => s.now))!;
    final failure = ref.watch(playerProvider.select((s) => s.failure));
    final prefs = ref.watch(playerPrefsProvider);
    final engine = ref.read(playerEngineProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(now.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headlineMedium),
        if (now.author != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            now.author!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge?.copyWith(color: muted),
          ),
        ],
        if (failure != null) ...[
          const SizedBox(height: Space.md),
          ErrorNotice(
            message: l10n.playerFailed,
            details: failure,
            action: FilledButton.tonal(onPressed: engine.play, child: Text(l10n.genericRetry)),
          ),
        ],
        const SizedBox(height: Space.xl),
        const _ChapterLine(),
        const _Scrubber(),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, box) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth < _controlsWidth ? _controlsWidth : box.maxWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    iconSize: 36,
                    tooltip: l10n.playerPreviousChapter,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      engine.previousChapter();
                    },
                  ),
                  SkipButton(seconds: prefs.skipBack.inSeconds, forward: false, onPressed: engine.skipBack),
                  const PlayPauseButton(),
                  SkipButton(seconds: prefs.skipForward.inSeconds, forward: true, onPressed: engine.skipForward),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    iconSize: 36,
                    tooltip: l10n.playerNextChapter,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      engine.nextChapter();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        const _ActionRow(),
      ],
    );
  }
}

/// Chapter title and "Chapter 7 of 32". Tapping opens the chapter list.
class _ChapterLine extends ConsumerWidget {
  const _ChapterLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (chapter, count) = ref.watch(playerProvider.select((s) => (s.chapter, s.now?.chapters.length ?? 0)));
    if (chapter == null) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.cover),
      onTap: () => showChaptersSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: Space.sm),
              Text(
                l10n.playerChapterOf(chapter.index + 1, count),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chapter or whole-book scrubber. Tap the times to switch. While dragging
/// the time follows the thumb; in book mode a light tick marks chapter
/// boundaries.
class _Scrubber extends ConsumerStatefulWidget {
  const _Scrubber();

  @override
  ConsumerState<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<_Scrubber> {
  Duration? _dragging;
  int? _lastChapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = ref.watch(playerProvider);
    final chapterMode = ref.watch(playerPrefsProvider.select((p) => p.chapterScrubber));
    final now = s.now!;
    final chapters = now.chapters;
    final position = _dragging ?? s.position;
    final chapter = chapters.isEmpty ? null : chapters[chapterIndexAt(chapters, _dragging ?? s.position)];
    final useChapter = chapterMode && chapter != null && chapters.length > 1;
    final start = useChapter ? chapter.start : Duration.zero;
    final end = useChapter ? chapter.end : now.duration;
    final span = (end - start).inMilliseconds;
    final value = span <= 0 ? 0.0 : ((position - start).inMilliseconds / span).clamp(0.0, 1.0);
    final elapsed = position - start;
    final left = atSpeed(end - position, s.speed);
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    void toggleScope() {
      HapticFeedback.selectionClick();
      ref.read(playerPrefsProvider.notifier).update((p) => p.copyWith(chapterScrubber: !p.chapterScrubber));
    }

    Duration at(double v) => start + Duration(milliseconds: (span * v).round());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            overlayShape: SliderComponentShape.noOverlay,
            trackHeight: 5,
            padding: const EdgeInsets.symmetric(vertical: Space.md),
          ),
          child: Slider(
            value: value,
            semanticFormatterCallback: (v) => formatClock(at(v) - start),
            label: l10n.playerPosition(useChapter ? l10n.playerScopeChapter : l10n.playerScopeBook),
            onChangeStart: (v) => setState(() {
              _dragging = at(v);
              _lastChapter = chapterIndexAt(chapters, _dragging!);
            }),
            onChanged: (v) {
              final target = at(v);
              final index = chapterIndexAt(chapters, target);
              if (!useChapter && index != _lastChapter) HapticFeedback.selectionClick();
              _lastChapter = index;
              setState(() => _dragging = target);
            },
            onChangeEnd: (v) {
              unawaited(ref.read(playerEngineProvider).seek(at(v)));
              setState(() => _dragging = null);
            },
          ),
        ),
        Row(
          children: [
            Semantics(
              button: true,
              label: useChapter ? l10n.playerShowBookTime : l10n.playerShowChapterTime,
              excludeSemantics: true,
              child: InkWell(
                onTap: toggleScope,
                borderRadius: BorderRadius.circular(Radii.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Text(formatClock(elapsed), style: timeStyle),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: InkWell(
                onTap: toggleScope,
                borderRadius: BorderRadius.circular(Radii.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Text(
                    useChapter
                        ? l10n.playerChapterLeft(timeLeftText(l10n, left))
                        : l10n.playerBookLeft(timeLeftText(l10n, left)),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: timeStyle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Speed, sleep, bookmark, chapters, Up next.
class _ActionRow extends ConsumerWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (speed, sleep, sleepLeft, queueLength) = ref.watch(
      playerProvider.select((s) => (s.speed, s.sleep, s.sleepRemaining, s.queue.length)),
    );
    final sleeping = sleep is! SleepOff;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () => showSpeedSheet(context),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurface, minimumSize: const Size(56, 48)),
          child: Text(
            formatSpeed(l10n, speed),
            semanticsLabel: '${l10n.playerSpeed}, ${formatSpeed(l10n, speed)}',
            style: theme.textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        if (sleeping)
          TextButton.icon(
            onPressed: () => showSleepSheet(context),
            style: TextButton.styleFrom(foregroundColor: scheme.primary, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.bedtime_rounded),
            label: Text(
              sleep is SleepAtChapterEnd || sleepLeft == null ? '' : formatClock(sleepLeft),
              semanticsLabel: sleep is SleepAtChapterEnd || sleepLeft == null
                  ? l10n.playerSleepAtChapterEnd
                  : l10n.playerSleepRemaining(formatClock(sleepLeft)),
              style: theme.textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.bedtime_outlined),
            tooltip: l10n.playerSleepTimer,
            onPressed: () => showSleepSheet(context),
          ),
        IconButton(
          icon: const Icon(Icons.bookmark_add_outlined),
          tooltip: l10n.playerBookmark,
          onPressed: () => addBookmarkHere(context, ref),
        ),
        IconButton(
          icon: const Icon(Icons.format_list_bulleted_rounded),
          tooltip: l10n.playerChapters,
          onPressed: () => showChaptersSheet(context),
        ),
        IconButton(
          icon: Badge(
            isLabelVisible: queueLength > 0,
            label: Text(queueLength.toString()),
            child: const Icon(Icons.queue_music_rounded),
          ),
          tooltip: l10n.playerQueue,
          onPressed: () => showQueueSheet(context),
        ),
      ],
    );
  }
}
