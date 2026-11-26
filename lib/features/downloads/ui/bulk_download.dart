// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/data/library_providers.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../data/download_manager.dart';
import '../data/offline_providers.dart';

// Downloading many books at once: Download all on a series, an author, a
// collection or a playlist, and the books picked with Select in Audiobooks.

/// The books of [books] a download would add: those of [account] (the
/// current server account) that are not on the phone and not on their way.
/// Failed downloads count again.
List<BookSummary> booksToDownload(List<BookSummary> books, Map<String, DownloadState> states, SourceId? account) {
  final seen = <String>{};
  return [
    for (final b in books)
      if (account != null &&
          b.ref.source == account &&
          seen.add(b.ref.key) &&
          !(states[b.ref.key]?.isComplete ?? false) &&
          !(states[b.ref.key]?.isActive ?? false))
        b,
  ];
}

/// Asks (how many books, how much space), then downloads the books of
/// [books] that are not on the phone yet. True when they were queued.
Future<bool> downloadBooks(BuildContext context, WidgetRef ref, List<BookSummary> books) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(absLibraryRepositoryProvider);
  final states = ref.read(downloadStatesProvider).value ?? const <String, DownloadState>{};
  final wanted = booksToDownload(books, states, repository?.source);
  if (repository == null || wanted.isEmpty) {
    showMessage(context, l10n.downloadManyNothing);
    return false;
  }
  // An episode's cached size is its whole show's: say no size then.
  var size = 0;
  if (!wanted.any((b) => b.ref.episodeId != null)) {
    try {
      size = await repository.sizeOfItems([for (final b in wanted) b.ref.itemId]);
    } on Object {
      size = 0;
    }
  }
  int? free;
  try {
    free = await ref.read(freeSpaceProvider.future);
  } on Object {
    free = null;
  }
  if (!context.mounted) return false;
  final room = free;
  final tight = size > 0 && room != null && size > room;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l10n.downloadManyTitle(wanted.length)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(size > 0 ? l10n.downloadManyBody(formatBytes(l10n, size)) : l10n.downloadManyBodyNoSize),
          if (tight) ...[
            const SizedBox(height: Space.md),
            Text(
              l10n.downloadManyLowSpace(formatBytes(l10n, room)),
              style: TextStyle(color: Theme.of(dialog).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.genericCancel)),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(l10n.downloadAction)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final added = await ref.read(downloadManagerProvider).enqueueItems([
      for (final b in wanted) (ref: b.ref, title: b.title),
    ]);
    unawaited(HapticFeedback.mediumImpact());
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.downloadManyAdded(added))));
    return true;
  } on Object catch (e) {
    if (context.mounted) showActionError(context, e);
    return false;
  }
}

/// "Download all" on a series, an author, a collection or a playlist.
/// Nothing for books on this phone or of another account. Says so when
/// every book is downloaded or on its way.
class DownloadAllButton extends ConsumerWidget {
  const DownloadAllButton({super.key, required this.books});

  final List<BookSummary> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(absLibraryRepositoryProvider.select((r) => r?.source));
    if (account == null || !books.any((b) => b.ref.source == account)) return const SizedBox.shrink();
    // Counts, not states: progress ticks of a running download do not
    // rebuild the button.
    final (left, running) = ref.watch(
      downloadStatesProvider.select((v) {
        final states = v.value ?? const <String, DownloadState>{};
        return (
          booksToDownload(books, states, account).length,
          books.where((b) => states[b.ref.key]?.isActive ?? false).length,
        );
      }),
    );
    final (icon, label) = left > 0
        ? (Icons.download_rounded, l10n.downloadAllInSeries)
        : running > 0
        ? (Icons.downloading_rounded, l10n.downloadAllRunning)
        : (Icons.download_done_rounded, l10n.downloadAllDone);
    return OutlinedButton.icon(
      onPressed: left > 0 ? () => downloadBooks(context, ref, books) : null,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}
