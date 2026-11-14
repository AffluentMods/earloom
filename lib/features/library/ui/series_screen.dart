// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/html_text.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/library_providers.dart';
import 'book_actions.dart';
import 'widgets/book_cards.dart';
import 'widgets/browse_layout.dart';
import 'widgets/collection_scaffold.dart';

/// The book a "Continue series" button plays: the first one not finished.
/// Null when every book is finished.
BookSummary? nextInSeries(List<BookSummary> books) {
  for (final b in books) {
    if (!(b.progress?.isFinished ?? false)) return b;
  }
  return null;
}

/// A series: its books in natural sequence order (1, 2, 2.5, 10), combined
/// progress, and one button that continues where the user is.
class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key, required this.source, required this.seriesId});

  final SourceId source;
  final String seriesId;

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> with RefreshingState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null || repository.source != widget.source) return;
    await runRefresh(() => repository.refreshSeries(widget.seriesId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final series = ref.watch(seriesProvider((source: widget.source, id: widget.seriesId)));
    final value = series.value;
    if (value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: series.isLoading
            ? const Center(child: ShelfSkeleton())
            : EmptyState(icon: Icons.auto_stories_outlined, title: l10n.seriesNotFound),
      );
    }
    final books = value.books;
    final finished = books.where((b) => b.progress?.isFinished ?? false).length;
    final started = books.any((b) => b.progress?.isStarted ?? false);
    final next = nextInSeries(books);
    final total = value.totalDuration;
    final subtitle = [
      l10n.countAndDuration(l10n.seriesBooksCount(books.length), formatDurationShort(l10n, total)),
      if (finished > 0) l10n.seriesProgress(finished, books.length),
    ].join('\n');
    final (label, target, startAt) = next == null
        ? (l10n.seriesListenAgain, books.isEmpty ? null : books.first, Duration.zero)
        : (started ? l10n.seriesContinue : l10n.seriesStart, next, null);
    return CollectionScaffold(
      title: value.name,
      subtitle: total > Duration.zero ? subtitle : null,
      themeBook: next ?? (books.isEmpty ? null : books.first),
      artwork: CoverStack(books: [?next, ...books.where((b) => b != next)], size: 200),
      refreshError: refreshError,
      onRefresh: () => _refresh(force: true),
      primaryAction: target == null
          ? null
          : FilledButton.icon(
              onPressed: () => BookActions.play(ref, target.ref, startAt: startAt),
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: Text(label),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
      below: value.description == null ? null : DescriptionText(html: value.description!, maxLines: 4),
      slivers: [
        SliverList.builder(
          itemCount: books.length,
          itemBuilder: (context, i) {
            final b = books[i];
            return BookListRow(
              book: b,
              place: 'series',
              leadingLabel: b.seriesSequence == null ? null : l10n.itemSeriesPosition(b.seriesSequence!, value.name),
            );
          },
        ),
        if (books.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(l10n.libraryEmpty, textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}
