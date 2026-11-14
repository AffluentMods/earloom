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
  const HeroCard({super.key, required this.book, this.onOpen, this.cover});

  final BookSummary book;

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
        child: _HeroContent(key: ValueKey(book.ref), book: book, onOpen: onOpen, cover: cover),
      ),
    );
  }
}

class _HeroContent extends ConsumerWidget {
  const _HeroContent({super.key, required this.book, this.onOpen, this.cover});

  final BookSummary book;
  final VoidCallback? onOpen;
  final BookSummary? cover;

  static const coverSize = 116.0;

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
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: bookSemantics(l10n, book),
                  button: true,
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BookCover(book: cover ?? book, size: coverSize, heroTag: tag, showProgress: false),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeContinueListening,
                              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: Space.xs),
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge?.copyWith(color: scheme.onSurface),
                            ),
                            if (book.authors.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                book.authorLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                              ),
                            ],
                            if (chapter != null && chapter.isNotEmpty) ...[
                              const SizedBox(height: Space.xs),
                              Text(
                                chapter,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Row(
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
                      onPressed: () =>
                          isCurrent ? BookActions.playOrPause(ref, book.ref) : BookActions.play(ref, book.ref),
                      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
                      label: Text(playing ? l10n.homePause : l10n.homeResume),
                      style: FilledButton.styleFrom(minimumSize: const Size(132, 52)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
