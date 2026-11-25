// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/cover_surfaces.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/ui/book_actions.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/book_cover.dart';
import '../../library/ui/widgets/progress_badge.dart';
import '../../player/player_controller.dart';

/// The book to go back to, big: its cover, where the user is, and a Resume
/// button that plays right here. The card takes the cover's colors and
/// cross-fades when the book changes.
class HeroCard extends ConsumerWidget {
  const HeroCard({super.key, required this.book, this.onOpen, this.onLongPress, this.cover, this.wide = false});

  final BookSummary book;

  /// What holding the card does (Home: take the book out of Continue
  /// listening).
  final VoidCallback? onLongPress;

  /// Tablet layout: a bigger cover with everything else beside it, so the
  /// card does not stretch a phone's layout across the screen.
  final bool wide;

  /// What the cover shows, when it is not [book] itself (an episode shows
  /// its show's cover).
  final BookSummary? cover;

  /// What tapping the card opens. Defaults to the book (or show) page; a
  /// podcast episode opens its episode sheet.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return BookCoverTheme(
      book: book,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : Motion.normal,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _HeroContent(
          key: ValueKey(book.ref),
          book: book,
          onOpen: onOpen,
          onLongPress: onLongPress,
          cover: cover,
          wide: wide,
        ),
      ),
    );
  }
}

class _HeroContent extends ConsumerWidget {
  const _HeroContent({super.key, required this.book, this.onOpen, this.onLongPress, this.cover, this.wide = false});

  final BookSummary book;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;
  final BookSummary? cover;
  final bool wide;

  static const coverSize = 116.0;
  static const wideCoverSize = 184.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final l10n = AppLocalizations.of(context);
    final isCurrent = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref));
    final playing = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref && s.playing));
    final livePosition = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref ? s.position : null));
    final chapter = ref.watch(playerProvider.select((s) => s.now?.ref == book.ref ? s.chapter?.title : null));
    final saved = book.progress;
    final duration = saved != null && saved.duration > Duration.zero ? saved.duration : book.duration;
    final position = livePosition ?? saved?.position ?? Duration.zero;
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final tag = coverHeroTag(book.ref, 'home-hero');
    final titleLines = <Widget>[
      Text(
        l10n.homeContinueListening,
        style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: Space.xs),
      Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (wide ? text.headlineMedium : text.titleLarge)?.copyWith(color: scheme.onSurface),
      ),
      if (book.authors.isNotEmpty) ...[
        SizedBox(height: wide ? Space.xs : 2),
        Text(
          book.authorLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (wide ? text.bodyLarge : text.bodyMedium)?.copyWith(color: scheme.onSurface),
        ),
      ],
      if (chapter != null && chapter.isNotEmpty) ...[
        const SizedBox(height: Space.xs),
        Text(
          chapter,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (wide ? text.bodyMedium : text.bodySmall)?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ];
    final progressRow = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThinProgressBar(value: fraction, height: 5),
              const SizedBox(height: Space.sm),
              Text(
                formatTimeLeft(l10n, duration - position),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.lg),
        FilledButton.icon(
          onPressed: () => isCurrent ? BookActions.playOrPause(ref, book.ref) : BookActions.play(ref, book.ref),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
          label: Text(playing ? l10n.homePause : l10n.homeResume),
          style: FilledButton.styleFrom(minimumSize: const Size(132, 52)),
        ),
      ],
    );
    final Widget content;
    if (wide) {
      // Cover on the left; title on top and the progress row at the bottom
      // of the column beside it, however tall the card ends up.
      content = Padding(
        padding: const EdgeInsets.all(Space.xl - Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: bookSemantics(l10n, book),
              button: true,
              excludeSemantics: true,
              onLongPress: onLongPress,
              onLongPressHint: onLongPress == null ? null : l10n.continueRemove,
              child: BookCover(book: cover ?? book, size: wideCoverSize, heroTag: tag, showProgress: false),
            ),
            const SizedBox(width: Space.xl),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: wideCoverSize),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: titleLines),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: Space.lg),
                      child: progressRow,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: bookSemantics(l10n, book),
              button: true,
              excludeSemantics: true,
              onLongPress: onLongPress,
              onLongPressHint: onLongPress == null ? null : l10n.continueRemove,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: cover ?? book, size: coverSize, heroTag: tag, showProgress: false),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: titleLines),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            progressRow,
          ],
        ),
      );
    }
    return AnimatedContainer(
      duration: Motion.normal,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.heroTint, Color.lerp(scheme.heroTint, scheme.surfaceContainerLow, 0.55)!],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen ?? () => BrowseNav.open(context, book, heroTag: tag),
          onLongPress: onLongPress,
          child: content,
        ),
      ),
    );
  }
}
