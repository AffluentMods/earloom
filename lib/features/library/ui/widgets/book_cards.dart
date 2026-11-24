// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/library/browse_models.dart';
import '../../../../core/library/models.dart';
import '../../../../core/library/source_id.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../browse_nav.dart';
import 'book_cover.dart';
import 'progress_badge.dart';

/// What a screen reader says for a book: title, authors, progress.
String bookSemantics(AppLocalizations l10n, BookSummary book) {
  final parts = [book.title, if (book.authors.isNotEmpty) book.authorLine];
  final p = book.progress;
  if (p != null && p.isFinished) {
    parts.add(l10n.genericFinished);
  } else if (p != null && p.isStarted) {
    parts.add(l10n.listenedPercent((p.fraction * 100).round()));
  }
  return parts.join(', ');
}

/// A cover with title and author under it, for grids and shelves.
class BookGridCard extends ConsumerWidget {
  const BookGridCard({
    super.key,
    required this.book,
    required this.width,
    required this.place,
    this.subtitle,
    this.selected = false,
    this.markPhoneBook = false,
  });

  final BookSummary book;
  final double width;

  /// Marks a book from the On this device library (see [BookCover]).
  final bool markPhoneBook;

  /// Where the card sits, to keep the cover's hero tag unique.
  final String place;

  /// Replaces the author line, for example "Book 2" in a series.
  final String? subtitle;

  /// The book open beside the list on tablets: ringed in the accent color.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final tag = coverHeroTag(book.ref, place);
    final secondLine = subtitle ?? (book.authors.isEmpty ? null : book.authorLine);
    final cover = BookCover(book: book, size: width, heroTag: tag, markPhoneBook: markPhoneBook);
    final onPhone = markPhoneBook && book.ref.source is LocalSource;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: selected,
        label: onPhone ? '${bookSemantics(l10n, book)}, ${l10n.sourceOnThisDevice}' : bookSemantics(l10n, book),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => BrowseNav.open(context, book, heroTag: tag),
          borderRadius: BorderRadius.circular(coverRadius(width)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(coverRadius(width)),
                  ),
                  child: cover,
                )
              else
                cover,
              const SizedBox(height: Space.sm),
              // Flexible: with large text the lines give way, never the
              // cover.
              // Two title lines need more room than the one line under them:
              // equal shares cut the title in half.
              Flexible(
                flex: 3,
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(height: 1.25, color: selected ? scheme.primary : null),
                ),
              ),
              if (secondLine != null) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    secondLine,
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

/// A book as a list row: small cover, title, author, length, progress.
class BookListRow extends ConsumerWidget {
  const BookListRow({
    super.key,
    required this.book,
    required this.place,
    this.leadingLabel,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.markPhoneBook = false,
  });

  final BookSummary book;
  final String place;

  /// Says "On this device" for a book from the On this device library.
  final bool markPhoneBook;

  /// A short label above the title, like "Book 2".
  final String? leadingLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The book open beside the list on tablets: on a tinted background.
  final bool selected;

  static const coverSize = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final tag = coverHeroTag(book.ref, place);
    final progress = book.progress;
    final details = [
      if (markPhoneBook && book.ref.source is LocalSource) l10n.sourceOnThisDevice,
      if (book.authors.isNotEmpty) book.authorLine,
      if (book.duration > Duration.zero)
        progress != null && progress.isStarted && !progress.isFinished
            ? formatTimeLeft(l10n, progress.remaining)
            : formatDurationShort(l10n, book.duration),
    ].join(' · ');
    return Semantics(
      button: true,
      label: bookSemantics(l10n, book),
      excludeSemantics: trailing == null,
      selected: selected,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () => BrowseNav.open(context, book, heroTag: tag),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              child: Row(
                children: [
                  BookCover(book: book, size: coverSize, heroTag: tag, shadow: false, showProgress: false),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingLabel != null)
                          Text(leadingLabel!, style: text.labelMedium?.copyWith(color: scheme.primary)),
                        Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (progress != null && progress.isStarted && !progress.isFinished) ...[
                          const SizedBox(height: Space.sm),
                          SizedBox(width: 120, child: ThinProgressBar(value: progress.fraction, height: 3)),
                        ],
                      ],
                    ),
                  ),
                  if (progress != null && progress.isFinished) ...[
                    const SizedBox(width: Space.sm),
                    Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
                  ],
                  if (trailing != null) ...[const SizedBox(width: Space.xs), trailing!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three covers fanned out, for a series or a book list.
class CoverStack extends StatelessWidget {
  const CoverStack({super.key, required this.books, required this.size});

  final List<BookSummary> books;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = books.take(3).toList();
    if (shown.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(coverRadius(size)),
        ),
        child: Icon(Icons.auto_stories_outlined, color: scheme.onSurfaceVariant, size: size * 0.3),
      );
    }
    final step = size * 0.09;
    final inner = size - step * (shown.length - 1);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              top: step * (shown.length - 1 - i),
              child: Opacity(
                opacity: i == 0 ? 1 : 0.92,
                child: BookCover(book: shown[i], size: inner, showProgress: false, shadow: i == 0),
              ),
            ),
        ],
      ),
    );
  }
}

/// A series as a card: fanned covers, name, book count.
class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.series, required this.width});

  final SeriesSummary series;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final count = series.bookCount > 0 ? l10n.seriesBooksCount(series.bookCount) : null;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: [series.name, ?count].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => BrowseNav.series(context, series.source, series.id),
          borderRadius: BorderRadius.circular(coverRadius(width)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverStack(books: series.books, size: width),
              const SizedBox(height: Space.sm),
              Flexible(
                child: Text(
                  series.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(height: 1.25),
                ),
              ),
              if (count != null)
                Flexible(
                  child: Text(
                    count,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a group's card says under its name: "Author, 729 books".
String bookGroupLine(AppLocalizations l10n, BookGroup group, int count) => switch (group.kind) {
  BookGroupKind.author => l10n.groupCardAuthor(count),
  BookGroupKind.series => l10n.groupCardSeries(count),
};

/// Opens the author or the series a group card stands for.
void openBookGroup(BuildContext context, BookGroup group) => switch (group.kind) {
  BookGroupKind.author => BrowseNav.author(context, group.source, group.id),
  BookGroupKind.series => BrowseNav.series(context, group.source, group.id),
};

/// An author or a series the user keeps together, as one card in a grid:
/// fanned covers, the name, what it is and how many books.
class BookGroupCard extends StatelessWidget {
  const BookGroupCard({super.key, required this.group, required this.books, required this.count, required this.width});

  final BookGroup group;
  final List<BookSummary> books;
  final int count;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final line = bookGroupLine(AppLocalizations.of(context), group, count);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: [group.name, line].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => openBookGroup(context, group),
          borderRadius: BorderRadius.circular(coverRadius(width)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverStack(books: books, size: width),
              const SizedBox(height: Space.sm),
              // Laid out like a book's card, so the grid stays even.
              Flexible(
                flex: 3,
                child: Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(height: 1.25),
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group as a list row, for the list layout of Audiobooks.
class BookGroupRow extends StatelessWidget {
  const BookGroupRow({super.key, required this.group, required this.books, required this.count});

  final BookGroup group;
  final List<BookSummary> books;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final line = bookGroupLine(AppLocalizations.of(context), group, count);
    return Semantics(
      button: true,
      label: [group.name, line].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openBookGroup(context, group),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              children: [
                CoverStack(books: books, size: BookListRow.coverSize),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(line, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An author as a row: photo, the whole name however long, how many books.
class AuthorRow extends StatelessWidget {
  const AuthorRow({super.key, required this.author});

  final AuthorSummary author;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final count = author.bookCount > 0 ? l10n.bookCountLabel(author.bookCount) : null;
    return Semantics(
      button: true,
      label: [author.name, ?count].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => BrowseNav.author(context, author.source, author.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
            child: Row(
              children: [
                AuthorAvatar(author: author, size: 56),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(author.name, style: text.titleMedium),
                      if (count != null) Text(count, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An author as a round photo with name and count.
class AuthorCard extends StatelessWidget {
  const AuthorCard({super.key, required this.author, required this.width});

  final AuthorSummary author;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final count = author.bookCount > 0 ? l10n.bookCountLabel(author.bookCount) : null;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: [author.name, ?count].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => BrowseNav.author(context, author.source, author.id),
          borderRadius: BorderRadius.circular(Radii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AuthorAvatar(author: author, size: width * 0.86),
                const SizedBox(height: Space.sm),
                Flexible(
                  child: Text(
                    author.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(height: 1.25),
                  ),
                ),
                if (count != null)
                  Flexible(
                    child: Text(
                      count,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
