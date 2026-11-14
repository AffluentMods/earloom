// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
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

enum BookListKind { collection, playlist }

/// A collection (read only, made on the server) or one of the user's
/// playlists (rename, delete, remove books, drag to reorder).
class BookListScreen extends ConsumerStatefulWidget {
  const BookListScreen.collection({super.key, required this.source, required this.id}) : kind = BookListKind.collection;

  const BookListScreen.playlist({super.key, required this.source, required this.id}) : kind = BookListKind.playlist;

  final SourceId source;
  final String id;
  final BookListKind kind;

  @override
  ConsumerState<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends ConsumerState<BookListScreen> with RefreshingState {
  /// The order while a drag is being saved, so the row does not jump back.
  List<BookSummary>? _pendingOrder;

  bool get _isPlaylist => widget.kind == BookListKind.playlist;

  Future<void> _refresh() async {
    final repository = ref.read(absLibraryRepositoryProvider);
    final list = _watch().value;
    if (repository == null || list == null) return;
    final libraryId = await _libraryId();
    if (libraryId == null) return;
    await runRefresh(
      () => _isPlaylist
          ? repository.refreshPlaylists(libraryId, force: true)
          : repository.refreshCollections(libraryId, force: true),
    );
  }

  Future<String?> _libraryId() async {
    final list = _watch().value;
    final first = list?.books.isEmpty ?? true ? null : list!.books.first.ref;
    if (first != null) return ref.read(libraryOfItemProvider(first).future);
    return ref.read(currentLibraryProvider).value?.id;
  }

  AsyncValue<BookListSummary?> _watch() {
    final key = (source: widget.source, id: widget.id);
    return ref.watch(_isPlaylist ? playlistProvider(key) : collectionProvider(key));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = _watch();
    final value = list.value;
    if (value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: list.isLoading
            ? const Center(child: ShelfSkeleton())
            : EmptyState(
                icon: _isPlaylist ? Icons.queue_music_rounded : Icons.collections_bookmark_outlined,
                title: _isPlaylist ? l10n.playlistNotFound : l10n.collectionNotFound,
              ),
      );
    }
    final books = _pendingOrder ?? value.books;
    final first = books.isEmpty ? null : books.first;
    return CollectionScaffold(
      title: value.name,
      subtitle: books.isEmpty
          ? null
          : l10n.countAndDuration(l10n.bookCountLabel(books.length), formatDurationShort(l10n, value.totalDuration)),
      themeBook: first,
      artwork: CoverStack(books: books, size: 200),
      refreshError: refreshError,
      onRefresh: _refresh,
      actions: [
        if (_isPlaylist)
          PopupMenuButton<String>(
            tooltip: l10n.itemMoreActions,
            onSelected: (action) => action == 'rename' ? _rename(value) : _delete(value),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.playlistRename)),
              PopupMenuItem(value: 'delete', child: Text(l10n.playlistDelete)),
            ],
          ),
      ],
      primaryAction: first == null
          ? null
          : FilledButton.icon(
              onPressed: () => BookActions.play(ref, first.ref),
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: Text(l10n.playlistPlayAll),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
      below: value.description == null ? null : DescriptionText(html: value.description!, maxLines: 3),
      slivers: [
        if (books.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(
                _isPlaylist ? l10n.playlistEmpty : l10n.collectionEmpty,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (!_isPlaylist)
          SliverList.builder(
            itemCount: books.length,
            itemBuilder: (_, i) => BookListRow(book: books[i], place: 'collection'),
          )
        else
          SliverReorderableList(
            itemCount: books.length,
            onReorderItem: (from, to) => _reorder(value, books, from, to),
            itemBuilder: (context, i) {
              final b = books[i];
              return Dismissible(
                key: ValueKey('playlist-${b.ref.key}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmRemove(books.length),
                onDismissed: (_) => _remove(value, b),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: BookListRow(
                    book: b,
                    place: 'playlist',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          tooltip: l10n.playlistRemoveItem,
                          onPressed: () async {
                            if (await _confirmRemove(books.length)) await _remove(value, b);
                          },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Semantics(
                            label: l10n.playlistReorderHandle,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<bool> _confirmRemove(int count) async {
    if (count > 1) return true;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.playlistRemoveLastTitle),
        content: Text(l10n.playlistRemoveLastBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.genericCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.genericRemove)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _remove(BookListSummary playlist, BookSummary book) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null) return;
    final l10n = AppLocalizations.of(context);
    final last = playlist.books.length <= 1;
    try {
      await repository.removeFromPlaylist(playlist.id, book.ref.itemId);
      if (!mounted) return;
      showMessage(context, last ? l10n.playlistDeleted : l10n.playlistRemoved);
      if (last && context.canPop()) context.pop();
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    }
  }

  Future<void> _reorder(BookListSummary playlist, List<BookSummary> current, int from, int to) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null) return;
    final order = [...current];
    final moved = order.removeAt(from);
    order.insert(to, moved);
    setState(() => _pendingOrder = order);
    try {
      await repository.reorderPlaylist(playlist.id, [for (final b in order) b.ref.itemId]);
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    } finally {
      if (mounted) setState(() => _pendingOrder = null);
    }
  }

  Future<void> _rename(BookListSummary playlist) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(absLibraryRepositoryProvider);
    final name = await askName(
      context,
      title: l10n.playlistRename,
      confirm: l10n.genericRename,
      initial: playlist.name,
    );
    if (name == null || repository == null || name == playlist.name) return;
    try {
      await repository.renamePlaylist(playlist.id, name);
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    }
  }

  Future<void> _delete(BookListSummary playlist) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(absLibraryRepositoryProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.playlistDelete),
        content: Text(l10n.playlistDeleteConfirm(playlist.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.genericCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.genericDelete),
          ),
        ],
      ),
    );
    if (ok != true || repository == null) return;
    try {
      await repository.deletePlaylist(playlist.id);
      if (!mounted) return;
      showMessage(context, l10n.playlistDeleted);
      if (context.canPop()) context.pop();
    } on Object catch (e) {
      if (mounted) showActionError(context, e);
    }
  }
}
