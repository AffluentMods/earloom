// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/book_cards.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../podcasts/ui/episode_sheet.dart';
import '../data/search_repository.dart';

/// The Search tab: as the user types (after a 300 ms pause) it searches the
/// current server library, or every library, and the books on this phone.
/// A newer query cancels the older one, so stale results never show.
/// Offline it searches the cache.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const debounce = Duration(milliseconds: 300);

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  CancelToken? _cancel;
  int _generation = 0;
  bool _allLibraries = false;
  bool _loading = false;
  SearchResults? _results;
  Object? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    if (value.trim().isEmpty) {
      _cancel?.cancel();
      _generation++;
      setState(() {
        _results = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(SearchScreen.debounce, () => _run(value.trim()));
  }

  List<String> _libraryIds() {
    final libraries = ref.read(absLibrariesProvider).value ?? const [];
    if (libraries.isEmpty) return const [];
    if (_allLibraries) return [for (final l in libraries) l.id];
    final current = ref.read(currentLibraryProvider).value;
    if (current != null && current.source is AbsSource) return [current.id];
    return [libraries.first.id];
  }

  Future<void> _run(String query) async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final results = await ref.read(searchRepositoryProvider).search(query, libraryIds: _libraryIds(), cancel: cancel);
      // Only the newest query may show its results.
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        _error = null;
      });
    } on AbsCancelled {
      // A newer query took over.
    } on Object catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _search(String query) {
    _field.text = query;
    _field.selection = TextSelection.collapsed(offset: query.length);
    _debounce?.cancel();
    unawaited(_run(query));
    unawaited(ref.read(searchRepositoryProvider).remember(query));
  }

  /// Remembers the query once the user acts on a result.
  void _remember() {
    final q = _field.text.trim();
    if (q.isNotEmpty) unawaited(ref.read(searchRepositoryProvider).remember(q));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final libraries = ref.watch(absLibrariesProvider).value ?? const [];
    final query = _field.text.trim();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSearch)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: SearchBar(
              controller: _field,
              focusNode: _focus,
              hintText: l10n.searchHint,
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 52),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (q) {
                if (q.trim().isNotEmpty) _search(q.trim());
              },
              trailing: [
                if (_field.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n.searchClear,
                    onPressed: () {
                      _field.clear();
                      _onChanged('');
                      _focus.requestFocus();
                    },
                  ),
              ],
            ),
          ),
          if (libraries.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: Text(l10n.searchAllLibraries),
                  selected: _allLibraries,
                  onSelected: (v) {
                    setState(() => _allLibraries = v);
                    if (query.isNotEmpty) unawaited(_run(query));
                  },
                ),
              ),
            ),
          SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _focus.unfocus(),
              child: query.isEmpty
                  ? _Recent(onPick: _search)
                  : _error != null && _results == null
                  ? Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: ErrorNotice(message: l10n.genericActionFailed, details: failureDetails(_error!)),
                    )
                  : _results == null
                  ? const SizedBox.shrink()
                  : _Results(results: _results!, onOpen: _remember),
            ),
          ),
        ],
      ),
    );
  }
}

class _Recent extends ConsumerWidget {
  const _Recent({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recent = ref.watch(recentSearchesProvider).value ?? const [];
    if (recent.isEmpty) {
      return EmptyState(icon: Icons.travel_explore_rounded, title: l10n.searchStartTitle, body: l10n.searchStartBody);
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SectionHeader(
          title: l10n.searchRecent,
          action: Semantics(
            label: l10n.searchClearRecentLabel,
            excludeSemantics: true,
            button: true,
            child: TextButton(
              onPressed: () => ref.read(searchRepositoryProvider).clearRecent(),
              child: Text(l10n.searchClearRecent),
            ),
          ),
        ),
        for (final q in recent)
          ListTile(
            minTileHeight: 52,
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            trailing: const Icon(Icons.north_west_rounded, size: 18),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results, required this.onOpen});

  final SearchResults results;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (results.isEmpty) {
      return ListView(
        children: [
          if (results.offline) const RefreshNotice(error: AbsUnreachable('offline search')),
          EmptyState(
            icon: Icons.search_off_rounded,
            title: l10n.searchNoResults(results.query),
            body: l10n.searchNoResultsBody,
          ),
        ],
      );
    }
    final library = ref.watch(currentLibraryProvider).value;
    final server = ref.watch(absLibraryRepositoryProvider);
    final serverLibraryId = library != null && library.source is AbsSource
        ? library.id
        : (ref.watch(absLibrariesProvider).value?.firstOrNull?.id);
    return Listener(
      onPointerDown: (_) => onOpen(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xxl),
        children: [
          if (results.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: InlineNotice(icon: Icons.cloud_off_rounded, message: l10n.searchOffline),
            ),
          if (results.books.isNotEmpty) ...[
            SectionHeader(title: l10n.searchGroupBooks),
            for (final b in results.books) BookListRow(book: b, place: 'search'),
          ],
          if (results.podcasts.isNotEmpty) ...[
            SectionHeader(title: l10n.searchGroupPodcasts),
            for (final b in results.podcasts) BookListRow(book: b, place: 'search-podcast'),
          ],
          if (results.episodes.isNotEmpty) ...[
            SectionHeader(title: l10n.searchGroupEpisodes),
            for (final b in results.episodes)
              BookListRow(book: b, place: 'search-episode', onTap: () => showEpisodeSheet(context, b.ref)),
          ],
          if (results.series.isNotEmpty)
            Shelf(
              title: l10n.searchGroupSeries,
              height: 120 + 72,
              itemCount: results.series.length,
              itemBuilder: (_, i) => SeriesCard(series: results.series[i], width: 120),
            ),
          if (results.authors.isNotEmpty)
            Shelf(
              title: l10n.searchGroupAuthors,
              height: 150,
              spacing: Space.md,
              itemCount: results.authors.length,
              itemBuilder: (_, i) => AuthorCard(author: results.authors[i], width: 96),
            ),
          if (results.narrators.isNotEmpty && server != null && serverLibraryId != null) ...[
            SectionHeader(title: l10n.searchGroupNarrators),
            for (final n in results.narrators)
              ListTile(
                minTileHeight: 56,
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: const Icon(Icons.record_voice_over_outlined),
                ),
                title: Text(n.name),
                subtitle: n.count > 0 ? Text(l10n.bookCountLabel(n.count)) : null,
                onTap: () => BrowseNav.filtered(context, server.source, serverLibraryId, FilterKind.narrator, n.name),
              ),
          ],
          if ((results.genres.isNotEmpty || results.tags.isNotEmpty) && server != null && serverLibraryId != null) ...[
            SectionHeader(title: l10n.searchGroupTags),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final g in results.genres)
                    ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: Text(g.name),
                      tooltip: l10n.searchGenre,
                      onPressed: () =>
                          BrowseNav.filtered(context, server.source, serverLibraryId, FilterKind.genre, g.name),
                    ),
                  for (final t in results.tags)
                    ActionChip(
                      avatar: const Icon(Icons.sell_outlined, size: 18),
                      label: Text(t.name),
                      tooltip: l10n.searchTag,
                      onPressed: () =>
                          BrowseNav.filtered(context, server.source, serverLibraryId, FilterKind.tag, t.name),
                    ),
                ],
              ),
            ),
          ],
          if (results.localBooks.isNotEmpty) ...[
            SectionHeader(title: l10n.searchGroupOnThisDevice),
            for (final b in results.localBooks) BookListRow(book: b, place: 'search-local'),
          ],
        ],
      ),
    );
  }
}
