// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/sync/outbox.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/offline_providers.dart';

/// A quiet row about changes that have not reached the server: how many wait,
/// and, when the server refused some, a way to see them (with "Copy
/// details") and dismiss them. Shows nothing when everything is sent.
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(outboxCountsProvider).value ?? const OutboxCounts();
    if (counts.pending == 0 && counts.dead == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (counts.dead > 0) {
      return ListTile(
        leading: Icon(Icons.sync_problem_rounded, color: scheme.error),
        title: Text(l10n.syncFailedChanges(counts.dead)),
        trailing: TextButton(onPressed: () => unawaited(_showDetails(context, ref)), child: Text(l10n.syncDetails)),
      );
    }
    return ListTile(
      leading: Icon(Icons.cloud_upload_outlined, color: scheme.onSurfaceVariant),
      title: Text(l10n.syncPendingChanges(counts.pending)),
    );
  }

  static String _kind(AppLocalizations l10n, OutboxKind kind) => switch (kind) {
    OutboxKind.progress => l10n.syncKindProgress,
    OutboxKind.markFinished => l10n.syncKindFinished,
    OutboxKind.bookmarkAdd || OutboxKind.bookmarkUpdate || OutboxKind.bookmarkDelete => l10n.syncKindBookmark,
    OutboxKind.localSession => l10n.syncKindSession,
    OutboxKind.playlistEdit => l10n.syncKindPlaylist,
  };

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    final queue = ref.read(outboxQueueProvider);
    final dead = await queue.deadEntries();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final details = [
      for (final e in dead)
        '${e.kind.name} ${e.itemId}${e.episodeId == null ? '' : '/${e.episodeId}'}: ${e.lastError ?? ''}',
    ].join('\n');
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.syncDetailsTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.syncDetailsBody),
              const SizedBox(height: Space.md),
              for (final e in dead)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Text(_kind(l10n, e.kind), style: Theme.of(dialog).textTheme.titleSmall),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
              if (dialog.mounted) {
                ScaffoldMessenger.maybeOf(dialog)?.showSnackBar(SnackBar(content: Text(l10n.genericDetailsCopied)));
              }
            },
            child: Text(l10n.genericCopyDetails),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialog);
              await queue.discardDead();
            },
            child: Text(l10n.syncDismiss),
          ),
        ],
      ),
    );
  }
}
