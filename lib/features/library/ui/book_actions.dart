// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../local_library/data/providers.dart';
import '../../player/player_controller.dart';
import '../data/library_providers.dart';
import 'widgets/browse_layout.dart';

/// What the browsing screens can do with a book, the same for both
/// sources. Playback goes through the player engine and never navigates.
abstract final class BookActions {
  /// Plays [book] (from [startAt], else where the user left off). Stays on
  /// the current screen: the mini player shows what plays.
  static Future<void> play(WidgetRef ref, ItemRef book, {Duration? startAt}) {
    unawaited(HapticFeedback.lightImpact());
    return ref.read(playerEngineProvider).playItem(book, startAt: startAt);
  }

  /// Play or pause when [book] is the loaded one, else start it.
  static Future<void> playOrPause(WidgetRef ref, ItemRef book) {
    final snapshot = ref.read(playerProvider);
    if (snapshot.now?.ref == book) {
      unawaited(HapticFeedback.lightImpact());
      return ref.read(playerEngineProvider).togglePlayPause();
    }
    return play(ref, book);
  }

  static Future<void> playNext(BuildContext context, WidgetRef ref, BookSummary book) async {
    await ref.read(playerEngineProvider).playNext(book.ref);
    if (context.mounted) showMessage(context, AppLocalizations.of(context).itemAddedToUpNext);
  }

  static Future<void> addToUpNext(BuildContext context, WidgetRef ref, BookSummary book) async {
    await ref.read(playerEngineProvider).addToQueue(book.ref);
    if (context.mounted) showMessage(context, AppLocalizations.of(context).itemAddedToUpNext);
  }

  /// Marks finished or not. Server books change in the cache at once and
  /// go back if the server says no.
  static Future<void> setFinished(BuildContext context, WidgetRef ref, BookSummary book, bool finished) async {
    final l10n = AppLocalizations.of(context);
    try {
      switch (book.ref.source) {
        case LocalSource():
          final repository = ref.read(localLibraryRepositoryProvider);
          finished ? await repository.markFinished(book.ref.itemId) : await repository.markUnfinished(book.ref.itemId);
        case AbsSource():
          final repository = ref.read(absLibraryRepositoryProvider);
          if (repository == null || repository.source != book.ref.source) return;
          await repository.setFinished(book.ref.itemId, finished: finished);
      }
      unawaited(HapticFeedback.mediumImpact());
      if (context.mounted) showMessage(context, finished ? l10n.itemMarkedFinished : l10n.itemMarkedUnfinished);
    } on Object catch (e) {
      if (context.mounted) showActionError(context, e);
    }
  }

  /// Asks, then deletes an imported book and its files. Returns true when
  /// it was deleted.
  static Future<bool> deleteLocal(BuildContext context, WidgetRef ref, BookSummary book) async {
    final repository = ref.read(localLibraryRepositoryProvider);
    final l10n = AppLocalizations.of(context);
    int? size;
    try {
      size = await repository.storageBytes(book.ref.itemId);
    } on Object {
      size = null;
    }
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.itemDeleteLocalTitle),
        content: Text(
          size == null || size == 0
              ? l10n.itemDeleteLocalBodyNoSize
              : l10n.itemDeleteLocalBody(formatBytes(l10n, size)),
        ),
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
    if (confirmed != true) return false;
    // The screen showing the book goes away with it: keep what is needed
    // to report back.
    final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
    try {
      if (ref.read(playerProvider).now?.ref == book.ref) await ref.read(playerEngineProvider).stop();
      await repository.deleteBook(book.ref.itemId);
      unawaited(HapticFeedback.heavyImpact());
      messenger?.showSnackBar(SnackBar(content: Text(l10n.itemDeleted)));
      return true;
    } on Object catch (e) {
      if (context.mounted) showActionError(context, e, message: l10n.genericSomethingWentWrong);
      return false;
    }
  }

  /// Lets the user pick one of their playlists (or make a new one) for a
  /// server book.
  static Future<void> addToPlaylist(BuildContext context, WidgetRef ref, BookSummary book, String libraryId) async {
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null || repository.source != book.ref.source) return;
    final l10n = AppLocalizations.of(context);
    unawaitedRefresh(() => repository.refreshPlaylists(libraryId));
    final choice = await showModalBottomSheet<_PlaylistChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _PlaylistPicker(libraryKey: (source: book.ref.source, libraryId: libraryId), book: book),
    );
    if (choice == null || !context.mounted) return;
    try {
      switch (choice) {
        case _NewPlaylist():
          final name = await askName(context, title: l10n.playlistNew, confirm: l10n.genericCreate);
          if (name == null) return;
          await repository.createPlaylist(libraryId, name, firstItemId: book.ref.itemId);
          if (context.mounted) showMessage(context, l10n.playlistAdded(name));
        case _ExistingPlaylist(:final playlist):
          if (playlist.books.any((b) => b.ref == book.ref)) {
            showMessage(context, l10n.playlistAlreadyIn(playlist.name));
            return;
          }
          await repository.addToPlaylist(playlist.id, book.ref.itemId);
          if (context.mounted) showMessage(context, l10n.playlistAdded(playlist.name));
      }
    } on Object catch (e) {
      if (context.mounted) showActionError(context, e);
    }
  }

  static void unawaitedRefresh(Future<void> Function() task) {
    task().catchError((Object _) {});
  }
}

/// Asks for a name (new playlist, rename). Null when cancelled.
Future<String?> askName(BuildContext context, {required String title, required String confirm, String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, confirm: confirm, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.confirm, this.initial});

  final String title;
  final String confirm;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).playlistNameRequired);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: l10n.playlistName, errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.genericCancel)),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

sealed class _PlaylistChoice {
  const _PlaylistChoice();
}

final class _NewPlaylist extends _PlaylistChoice {
  const _NewPlaylist();
}

final class _ExistingPlaylist extends _PlaylistChoice {
  const _ExistingPlaylist(this.playlist);
  final BookListSummary playlist;
}

class _PlaylistPicker extends ConsumerWidget {
  const _PlaylistPicker({required this.libraryKey, required this.book});

  final LibraryKey libraryKey;
  final BookSummary book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final playlists = ref.watch(playlistsProvider(libraryKey)).value ?? const [];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(l10n.playlistChooseTitle, style: text.titleLarge),
          ),
          ListTile(
            minTileHeight: 56,
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.add_rounded),
            ),
            title: Text(l10n.playlistNew),
            onTap: () => Navigator.pop(context, const _NewPlaylist()),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in playlists)
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(p.name),
                    subtitle: Text(l10n.bookCountLabel(p.books.length)),
                    trailing: p.books.any((b) => b.ref == book.ref)
                        ? Icon(Icons.check_rounded, color: scheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, _ExistingPlaylist(p)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}
