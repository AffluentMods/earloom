// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/library_providers.dart';

/// Picks the sort field and direction. Null when dismissed.
Future<LibraryQuery?> showSortSheet(BuildContext context, LibraryQuery query, {required bool local}) {
  return showModalBottomSheet<LibraryQuery>(
    context: context,
    useSafeArea: true,
    builder: (_) => _SortSheet(query: query, local: local),
  );
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.query, required this.local});

  final LibraryQuery query;
  final bool local;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late LibraryQuery _query = widget.query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = [
      (LibrarySort.title, l10n.librarySortTitle),
      (LibrarySort.author, l10n.librarySortAuthor),
      (LibrarySort.addedAt, l10n.librarySortAdded),
      (LibrarySort.duration, l10n.librarySortDuration),
      (LibrarySort.progress, l10n.librarySortProgress),
      if (!widget.local) (LibrarySort.publishedYear, l10n.librarySortPublished),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text(l10n.librarySort, style: Theme.of(context).textTheme.titleLarge),
            ),
            RadioGroup<LibrarySort>(
              groupValue: _query.sort,
              onChanged: (v) => Navigator.pop(context, _query.copyWith(sort: v)),
              child: Column(
                children: [
                  for (final (sort, label) in options) RadioListTile<LibrarySort>(value: sort, title: Text(label)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.librarySortAscending),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.librarySortDescending),
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_query.descending},
                onSelectionChanged: (v) {
                  setState(() => _query = _query.copyWith(descending: v.first));
                  Navigator.pop(context, _query);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks filters from the library's own genres, tags, series, authors,
/// narrators and languages. Null when dismissed without changes.
Future<LibraryQuery?> showFilterSheet(BuildContext context, LibraryKey key, LibraryQuery query) {
  return showModalBottomSheet<LibraryQuery>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => _FilterSheet(libraryKey: key, query: query, controller: controller),
    ),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.libraryKey, required this.query, required this.controller});

  final LibraryKey libraryKey;
  final LibraryQuery query;
  final ScrollController controller;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late LibraryQuery _query = widget.query;

  void _toggle(LibraryFilter filter) {
    setState(() {
      _query = _query.filterOf(filter.kind) == filter ? _query.without(filter) : _query.withFilter(filter);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final choices = ref.watch(filterChoicesProvider(widget.libraryKey)).value ?? FilterChoices.empty;
    final isLocal = widget.libraryKey.source is LocalSource;

    Widget group(String title, List<LibraryFilter> filters) {
      if (filters.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final f in filters)
                  FilterChip(
                    label: Text(f.label),
                    selected: _query.filterOf(f.kind) == f,
                    onSelected: (_) => _toggle(f),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.sm, 0),
          child: Row(
            children: [
              Expanded(child: Text(l10n.libraryFilter, style: text.titleLarge)),
              TextButton(
                onPressed: _query.filters.isEmpty
                    ? null
                    : () => setState(() => _query = _query.copyWith(filters: const [])),
                child: Text(l10n.filterClearAll),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              group(l10n.filterProgress, [
                LibraryFilter(FilterKind.progress, ProgressFilterValue.notStarted, label: l10n.filterNotStarted),
                LibraryFilter(FilterKind.progress, ProgressFilterValue.inProgress, label: l10n.filterInProgress),
                LibraryFilter(FilterKind.progress, ProgressFilterValue.finished, label: l10n.filterFinished),
              ]),
              if (!isLocal)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
                  child: SwitchListTile(
                    title: Text(l10n.filterDownloadedOnly),
                    value: _query.filterOf(FilterKind.downloaded) != null,
                    onChanged: (_) => _toggle(const LibraryFilter(FilterKind.downloaded, 'true')),
                  ),
                ),
              group(l10n.filterGenres, [for (final g in choices.genres) LibraryFilter(FilterKind.genre, g)]),
              group(l10n.filterTags, [for (final t in choices.tags) LibraryFilter(FilterKind.tag, t)]),
              group(l10n.librarySeries, [
                for (final (id, name) in choices.series) LibraryFilter(FilterKind.series, id, label: name),
              ]),
              group(l10n.libraryAuthors, [for (final a in choices.authors) LibraryFilter(FilterKind.author, a)]),
              group(l10n.filterNarrators, [for (final n in choices.narrators) LibraryFilter(FilterKind.narrator, n)]),
              group(l10n.filterLanguages, [for (final n in choices.languages) LibraryFilter(FilterKind.language, n)]),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _query),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(l10n.filterShowBooks),
            ),
          ),
        ),
      ],
    );
  }
}
