// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/cover_surfaces.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/html_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../library/ui/widgets/progress_badge.dart';
import '../../downloads/ui/download_button.dart';
import '../../local_library/ui/edit_book_sheet.dart';
import '../../player/player_controller.dart';
import '../../podcasts/ui/show_screen.dart';
import '../../stats/ui/book_listening_card.dart';
import 'book_bookmarks.dart';

/// One book, themed with its cover: header, the main play button, progress,
/// description, chapters, details and more in the series. Renders from the
/// cache at once and refreshes in the background.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId, this.source, this.heroTag});

  final String itemId;

  /// Null means the current server account (the `earloom://item/<id>` deep
  /// link).
  final SourceId? source;

  /// The tag of the cover that was tapped, so it flies into the header.
  final Object? heroTag;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> with RefreshingState {
  ItemRef? get _ref {
    final source = widget.source ?? ref.read(accountSessionProvider)?.source;
    return source == null ? null : ItemRef(source, widget.itemId);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final item = _ref;
    if (item == null) return;
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null || repository.source != item.source) return;
    await runRefresh(() => repository.refreshItem(item.itemId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final item = _ref;
    if (item == null) return const _NotFound();
    // Refetch when playback of this book ends (progress changed for sure).
    ref.listen(playerProvider.select((s) => s.now?.ref), (previous, next) {
      if (previous == item && next != item) _refresh(force: true);
    });
    final detail = ref.watch(bookDetailProvider(item));
    return detail.when(
      skipLoadingOnReload: true,
      loading: () => const _LoadingDetail(),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: ErrorNotice(message: AppLocalizations.of(context).genericSomethingWentWrong, details: '$e'),
        ),
      ),
      data: (book) {
        if (book == null) return const _NotFound();
        // A podcast (from a link or a notification) is a show.
        if (book.summary.isPodcast) return ShowScreen(show: item, heroTag: widget.heroTag);
        return BookCoverTheme(
          book: book.summary,
          child: _DetailBody(
            detail: book,
            heroTag: widget.heroTag ?? coverHeroTag(item, 'detail'),
            refreshError: refreshError,
            onRefresh: () => _refresh(force: true),
          ),
        );
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.heroTag, required this.refreshError, required this.onRefresh});

  final BookDetail detail;
  final Object heroTag;
  final Object? refreshError;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final book = detail.summary;
    final libraryId = ref.watch(libraryOfItemProvider(book.ref)).value;
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = (width * 0.6).clamp(180.0, 280.0);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: l10n.itemMoreActions,
            onPressed: () => _showMore(context, ref, book, libraryId),
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
            stops: const [0, 0.55],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              MediaQuery.paddingOf(context).top + kToolbarHeight,
              0,
              MediaQuery.paddingOf(context).bottom + Space.xxl,
            ),
            children: [
              RefreshNotice(error: refreshError, padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg)),
              Center(
                child: BookCover(book: book, size: coverSize, heroTag: heroTag, showProgress: false),
              ),
              const SizedBox(height: Space.xl),
              _Pad(
                child: _Header(detail: detail, libraryId: libraryId),
              ),
              const SizedBox(height: Space.xl),
              _Pad(child: _PlayButton(book: book)),
              _Pad(child: _ProgressLine(book: book)),
              const SizedBox(height: Space.lg),
              _Pad(
                child: _ActionRow(book: book, libraryId: libraryId),
              ),
              if (detail.descriptionHtml != null && detail.descriptionHtml!.trim().isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                _Pad(child: DescriptionText(html: detail.descriptionHtml!)),
              ],
              if (detail.chapters.length > 1) _Chapters(detail: detail),
              BookBookmarks(itemRef: book.ref, chapters: detail.chapters),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
                child: BookListeningCard(itemRef: book.ref),
              ),
              _Details(detail: detail, libraryId: libraryId),
              _MoreInSeries(detail: detail),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMore(BuildContext context, WidgetRef ref, BookSummary book, String? libraryId) async {
    final l10n = AppLocalizations.of(context);
    final isLocal = book.ref.source is LocalSource;
    final repository = ref.read(absLibraryRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: Text(l10n.queuePlayNext),
              onTap: () => Navigator.pop(context, 'next'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(l10n.queueAdd),
              onTap: () => Navigator.pop(context, 'queue'),
            ),
            if (!isLocal && libraryId != null)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(l10n.itemAddToPlaylist),
                onTap: () => Navigator.pop(context, 'playlist'),
              ),
            if (isLocal) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.itemEdit),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                title: Text(l10n.itemDeleteLocal, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
            if (!isLocal && repository != null)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(l10n.itemOpenOnServer),
                onTap: () => Navigator.pop(context, 'web'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'next':
        await BookActions.playNext(context, ref, book);
      case 'queue':
        await BookActions.addToUpNext(context, ref, book);
      case 'playlist':
        await BookActions.addToPlaylist(context, ref, book, libraryId!);
      case 'edit':
        await showEditBookSheet(context, book.ref.itemId);
      case 'delete':
        final router = GoRouter.of(context);
        final deleted = await BookActions.deleteLocal(context, ref, book);
        if (deleted && router.canPop()) router.pop();
      case 'web':
        final base = repository!.client.baseUrl;
        await launchUrl(
          base.replace(path: '${base.path}/item/${book.ref.itemId}'),
          mode: LaunchMode.externalApplication,
        );
    }
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.xl),
    child: child,
  );
}

/// Title, subtitle, author and narrator links, series link.
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.libraryId});

  final BookDetail detail;
  final String? libraryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final l10n = AppLocalizations.of(context);
    final book = detail.summary;
    final source = book.ref.source;
    final series = detail.series.isNotEmpty
        ? detail.series
        : [
            if (book.seriesName != null)
              SeriesMembership(id: book.seriesName!, name: book.seriesName!, sequence: book.seriesSequence),
          ];
    final canLinkSeries = source is LocalSource || detail.series.isNotEmpty;
    return Column(
      children: [
        Semantics(
          header: true,
          child: Text(
            book.title,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
        ),
        if (book.subtitle != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            book.subtitle!,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (book.authors.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          _NameLinks(
            names: book.authors,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
            onTap: (name) {
              final id = source is LocalSource ? name : detail.authorIds[name];
              if (id != null) {
                BrowseNav.author(context, source, id);
              } else if (libraryId != null) {
                BrowseNav.filtered(context, source, libraryId!, FilterKind.author, name);
              }
            },
          ),
        ],
        if (book.narrators.isNotEmpty) ...[
          const SizedBox(height: 2),
          // One line: "Narrated by" sits in the same wrap as the names, so
          // it only breaks when the names do not fit beside it.
          _NameLinks(
            leading: l10n.itemNarratorsLabel,
            names: book.narrators,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            onTap: libraryId == null
                ? null
                : (name) => BrowseNav.filtered(context, source, libraryId!, FilterKind.narrator, name),
          ),
        ],
        for (final s in series) ...[
          const SizedBox(height: Space.md),
          ActionChip(
            avatar: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(s.sequence == null ? s.name : l10n.itemSeriesPosition(s.sequence!, s.name)),
            onPressed: canLinkSeries ? () => BrowseNav.series(context, source, s.id) : null,
          ),
        ],
      ],
    );
  }
}

/// Names separated by commas, each one a link.
class _NameLinks extends StatelessWidget {
  const _NameLinks({required this.names, required this.style, required this.onTap, this.leading});

  /// Plain text before the names ("Narrated by").
  final String? leading;
  final List<String> names;
  final TextStyle? style;
  final void Function(String name)? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (leading != null)
          Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: Text(leading!, style: style),
          ),
        for (final (i, name) in names.indexed)
          Semantics(
            button: onTap != null,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(name),
              borderRadius: BorderRadius.circular(Space.sm),
              // Centered in the tap area, so the names line up with the
              // "Narrated by" label next to them.
              // Align, not Container.alignment: inside a Wrap that would
              // stretch each name to a full line of its own.
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: Space.xs),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(i < names.length - 1 ? '$name,' : name, style: style),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Play, Resume with time left, Pause for the playing book, or Listen
/// again. Plays without leaving the screen.
class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.book});

  final BookSummary book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref));
    final playing = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref && s.playing));
    final buffering = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref && s.buffering));
    final progress = book.progress;
    final (IconData icon, String label, Duration? startAt) = switch (progress) {
      _ when playing => (Icons.pause_rounded, l10n.itemPause, null),
      final p? when p.isFinished && !current => (Icons.replay_rounded, l10n.itemListenAgain, Duration.zero),
      // Time left is right below, on the progress line.
      final p? when p.isStarted => (Icons.play_arrow_rounded, l10n.itemResume, null),
      _ => (
        Icons.play_arrow_rounded,
        book.duration > Duration.zero
            ? l10n.itemActionWithDetail(l10n.itemPlay, formatDurationShort(l10n, book.duration))
            : l10n.itemPlay,
        null,
      ),
    };
    return FilledButton.icon(
      onPressed: () =>
          current ? BookActions.playOrPause(ref, book.ref) : BookActions.play(ref, book.ref, startAt: startAt),
      icon: buffering
          ? SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
            )
          : Icon(icon, size: 28),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    );
  }
}

class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({required this.book});

  final BookSummary book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // While this book plays, follow the player instead of the saved
    // progress, which only changes every few seconds.
    final live = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref ? s.position : null));
    final saved = book.progress;
    final duration = saved != null && saved.duration > Duration.zero ? saved.duration : book.duration;
    if (duration <= Duration.zero) return const SizedBox.shrink();
    final position = live ?? saved?.position ?? Duration.zero;
    final finished = live == null && (saved?.isFinished ?? false);
    if (!finished && position < const Duration(seconds: 5)) return const SizedBox.shrink();
    final fraction = finished ? 1.0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final left = duration - position;
    final style = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        children: [
          ThinProgressBar(value: fraction, height: 6),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  finished
                      ? (saved?.finishedAt == null
                            ? l10n.genericFinished
                            : l10n.itemFinishedOn(DateFormat.yMMMd(l10n.localeName).format(saved!.finishedAt!)))
                      : l10n.itemListened(formatDurationShort(l10n, position)),
                  style: style,
                ),
              ),
              if (!finished)
                Text(
                  l10n.itemTimeLeftPercent(formatTimeLeft(l10n, left), (fraction * 100).round()),
                  style: style,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mark finished, add to playlist, up next.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.book, required this.libraryId});

  final BookSummary book;
  final String? libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finished = book.progress?.isFinished ?? false;
    final isServer = book.ref.source is AbsSource;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isServer)
          Expanded(
            child: Center(
              child: DownloadButton(itemRef: book.ref, title: book.title, compact: true),
            ),
          ),
        Expanded(
          child: _Action(
            icon: finished ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
            label: finished ? l10n.itemFinishedShort : l10n.itemMarkFinished,
            semanticLabel: finished ? l10n.itemMarkUnfinished : l10n.itemMarkFinished,
            selected: finished,
            onTap: () => BookActions.setFinished(context, ref, book, !finished),
          ),
        ),
        if (isServer && libraryId != null)
          Expanded(
            child: _Action(
              icon: Icons.playlist_add_rounded,
              label: l10n.itemPlaylistShort,
              semanticLabel: l10n.itemAddToPlaylist,
              onTap: () => BookActions.addToPlaylist(context, ref, book, libraryId!),
            ),
          ),
        Expanded(
          child: _Action(
            icon: Icons.queue_rounded,
            label: l10n.queuePlayNext,
            onTap: () => BookActions.playNext(context, ref, book),
          ),
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
                  maxLines: 2,
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

/// The chapter list: the current one highlighted, tap to play from there.
class _Chapters extends ConsumerStatefulWidget {
  const _Chapters({required this.detail});

  final BookDetail detail;

  @override
  ConsumerState<_Chapters> createState() => _ChaptersState();
}

class _ChaptersState extends ConsumerState<_Chapters> {
  static const _collapsedCount = 6;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final book = widget.detail.summary;
    final chapters = widget.detail.chapters;
    final playerIndex = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref ? s.chapterIndex : null));
    final p = book.progress;
    final current =
        playerIndex ??
        (p != null && p.isStarted && !p.isFinished ? chapters.indexWhere((c) => c.contains(p.position)) : -1);
    // Collapsed, the list shows a window around the current chapter.
    final start = _all || current < 0
        ? 0
        : (current - 1).clamp(0, (chapters.length - _collapsedCount).clamp(0, chapters.length));
    final shown = _all ? chapters : chapters.skip(start).take(_collapsedCount).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.itemChapters,
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.xl, Space.sm, Space.sm),
            action: Text(
              l10n.itemChapterCount(chapters.length),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final c in shown)
            _ChapterRow(
              chapter: c,
              current: c.index == current,
              onTap: () => BookActions.play(ref, book.ref, startAt: c.start),
            ),
          if (chapters.length > _collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? l10n.itemShowFewerChapters : l10n.itemShowAllChapters(chapters.length)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.current, required this.onTap});

  final Chapter chapter;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final foreground = current ? scheme.onSecondaryContainer : scheme.onSurface;
    final secondary = current ? foreground : scheme.onSurfaceVariant;
    final title = chapter.title.isEmpty ? l10n.chapterNumber(chapter.index + 1) : chapter.title;
    return Semantics(
      button: true,
      selected: current,
      label: [title, formatDurationShort(l10n, chapter.duration), if (current) l10n.itemCurrentChapter].join(', '),
      hint: l10n.itemPlayFromChapter(title),
      excludeSemantics: true,
      child: Material(
        color: current ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Space.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Space.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: current
                        ? Icon(Icons.graphic_eq_rounded, size: 20, color: foreground)
                        : Text(
                            NumberFormat.decimalPattern(l10n.localeName).format(chapter.index + 1),
                            style: theme.textTheme.labelMedium?.copyWith(color: secondary),
                          ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: foreground),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    _clock(chapter.start),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "1:02:05" or "12:05": a start time, like a track list.
  static String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

/// Genres and tags as chips (tap to see those books), then the facts.
class _Details extends ConsumerWidget {
  const _Details({required this.detail, required this.libraryId});

  final BookDetail detail;
  final String? libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final book = detail.summary;
    final source = book.ref.source;
    final rows = <(String, String)>[
      if (book.duration > Duration.zero) (l10n.itemLength, formatDurationShort(l10n, book.duration)),
      if (detail.publisher != null) (l10n.itemPublisher, detail.publisher!),
      if (detail.publishedYear != null) (l10n.itemPublished, detail.publishedYear!),
      if (detail.language != null) (l10n.itemLanguage, detail.language!),
      if (detail.fileFormat != null) (l10n.itemFormat, detail.fileFormat!.toUpperCase()),
      if (detail.bitRate != null) (l10n.itemBitRate, l10n.itemBitRateValue((detail.bitRate! / 1000).round())),
      if (detail.sizeBytes != null && detail.sizeBytes! > 0) (l10n.itemSize, formatBytes(l10n, detail.sizeBytes!)),
      if (detail.isbn != null) (l10n.itemIsbn, detail.isbn!),
      if (detail.asin != null) (l10n.itemAsin, detail.asin!),
      if (source is LocalSource) (l10n.itemSource, l10n.sourceOnThisDevice),
    ];
    final chips = [
      for (final g in detail.genres) (FilterKind.genre, g),
      for (final t in detail.tags) (FilterKind.tag, t),
    ];
    if (rows.isEmpty && chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.itemDetails,
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.xl, Space.sm, Space.sm),
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final (kind, value) in chips)
                    ActionChip(
                      label: Text(value),
                      onPressed: libraryId == null || source is LocalSource
                          ? null
                          : () => BrowseNav.filtered(context, source, libraryId!, kind, value),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Space.md),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(label, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: SelectableText(value, style: text.bodyMedium)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreInSeries extends ConsumerWidget {
  const _MoreInSeries({required this.detail});

  final BookDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = detail.summary;
    final source = book.ref.source;
    final seriesId = detail.series.isNotEmpty
        ? detail.series.first.id
        : (source is LocalSource ? book.seriesName : null);
    if (seriesId == null) return const SizedBox.shrink();
    final series = ref.watch(seriesProvider((source: source, id: seriesId))).value;
    final others = series?.books.where((b) => b.ref != book.ref).toList() ?? const [];
    if (series == null || others.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    const width = 128.0;
    return Shelf(
      title: l10n.itemMoreInSeries,
      height: cardShelfHeight(context, width),
      itemCount: others.length,
      action: TextButton(
        onPressed: () => BrowseNav.series(context, source, seriesId),
        child: Text(l10n.genericSeeAll),
      ),
      itemBuilder: (context, i) {
        final b = others[i];
        return BookGridCard(
          book: b,
          width: width,
          place: 'detail-series',
          subtitle: b.seriesSequence == null ? null : l10n.itemSeriesPosition(b.seriesSequence!, series.name),
        );
      },
    );
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Column(
            children: [
              SkeletonBox(width: 220, height: 220, radius: Radii.cover),
              SizedBox(height: Space.xl),
              SkeletonBox(width: 240, height: 24),
              SizedBox(height: Space.sm),
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: Space.xl),
              SkeletonBox(height: 56, radius: Radii.pill),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.menu_book_outlined,
        title: l10n.itemNotFound,
        body: l10n.itemNotFoundBody,
      ),
    );
  }
}
