// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/ui/browse_nav.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../data/podcast_json.dart';
import '../data/podcast_providers.dart';
import 'admin_actions.dart';

/// Opens the add podcast flow for [libraryId] (admins only).
Future<void> openAddPodcast(BuildContext context, String libraryId) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => AddPodcastScreen(libraryId: libraryId)));

/// Adds a show to a podcast library (docs/plan/06-phase5-podcasts.md 5.5):
/// search through the server (or paste a feed address), preview the feed
/// the server read, choose the library folder, add. Search results show no
/// artwork: it would load from the search provider's servers, not the
/// user's own.
class AddPodcastScreen extends ConsumerStatefulWidget {
  const AddPodcastScreen({super.key, required this.libraryId});

  final String libraryId;

  @override
  ConsumerState<AddPodcastScreen> createState() => _AddPodcastScreenState();
}

class _AddPodcastScreenState extends ConsumerState<AddPodcastScreen> {
  final _field = TextEditingController();
  bool _searching = false;
  List<PodcastSearchResult>? _results;
  Object? _error;
  FeedPreview? _preview;
  List<LibraryFolder> _folders = const [];
  LibraryFolder? _folder;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  static bool _isFeed(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    final repository = ref.read(podcastRepositoryProvider);
    if (query.isEmpty || repository == null) return;
    if (_isFeed(query)) return _openPreview(query);
    setState(() {
      _searching = true;
      _error = null;
      _preview = null;
    });
    try {
      final region = await repository.searchRegion(widget.libraryId);
      final results = await repository.searchPodcasts(query, country: region);
      if (mounted) setState(() => _results = results);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openPreview(String feedUrl) async {
    final repository = ref.read(podcastRepositoryProvider);
    if (repository == null) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final preview = await repository.previewFeed(feedUrl);
      final folders = await repository.libraryFolders(widget.libraryId);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _folders = folders;
        _folder = folders.isEmpty ? null : folders.first;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(podcastRepositoryProvider);
    final preview = _preview;
    final folder = _folder;
    if (repository == null || preview == null || folder == null) return;
    final ok = await confirmAdminAction(
      context,
      title: l10n.podcastAdminAdd,
      body: l10n.podcastAdminAddConfirm(preview.title, folder.fullPath),
    );
    if (!ok || !mounted) return;
    try {
      final id = await withProgress(
        context,
        () => repository.addPodcast(libraryId: widget.libraryId, folder: folder, feed: preview),
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final router = context;
      showMessage(context, l10n.podcastAdminAdded(preview.title));
      navigator.pop();
      if (id != null && router.mounted) BrowseNav.show(router, ItemRef(repository.source, id));
    } on Object catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.podcastAdminAdd),
        leading: preview == null ? null : BackButton(onPressed: () => setState(() => _preview = null)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: SearchBar(
              controller: _field,
              hintText: l10n.podcastAdminSearchHint,
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 52),
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.url,
              onSubmitted: (q) => unawaited(_search(q)),
            ),
          ),
          SizedBox(height: 2, child: _searching ? const LinearProgressIndicator(minHeight: 2) : null),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xxl),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: ErrorNotice(
                      message: adminErrorText(l10n, _error!),
                      details: failureDetails(_error!),
                    ),
                  ),
                if (preview != null) ...[
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: FeedPreviewCard(preview: preview),
                  ),
                  SectionHeader(title: l10n.podcastAdminChooseFolder),
                  if (_folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Text(l10n.podcastAdminNoFolders, style: theme.textTheme.bodyMedium),
                    )
                  else
                    RadioGroup<LibraryFolder>(
                      groupValue: _folder,
                      onChanged: (f) => setState(() => _folder = f),
                      child: Column(
                        children: [
                          for (final f in _folders)
                            RadioListTile<LibraryFolder>(
                              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                              value: f,
                              title: Text(f.fullPath),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: FilledButton.icon(
                      onPressed: _folder == null || _searching ? null : _add,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.podcastAdminAdd),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ] else if (_results != null && _results!.isEmpty)
                  EmptyState(icon: Icons.search_off_rounded, title: l10n.podcastAdminNoResults)
                else if (_results != null)
                  for (final r in _results!)
                    ListTile(
                      minTileHeight: 72,
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
                        child: const Icon(Icons.podcasts_rounded),
                      ),
                      title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [?r.author, if (r.episodeCount > 0) l10n.podcastEpisodes(r.episodeCount)].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: _searching ? null : () => _openPreview(r.feedUrl),
                    )
                else
                  EmptyState(
                    icon: Icons.podcasts_rounded,
                    title: l10n.podcastAdminSearchTitle,
                    body: l10n.podcastAdminSearchBody,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
