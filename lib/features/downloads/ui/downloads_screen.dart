// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Active and finished downloads, with storage use
/// (docs/plan/05-phase4-offline.md 4.4).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../player/player_controller.dart';
import '../data/download_manager.dart';
import '../data/offline_providers.dart';
import 'download_button.dart';
import 'sync_status.dart';

enum DownloadSort { date, title, size }

final _sortProvider = NotifierProvider.autoDispose<_SortController, DownloadSort>(_SortController.new);

class _SortController extends Notifier<DownloadSort> {
  @override
  DownloadSort build() => DownloadSort.date;

  void set(DownloadSort value) => state = value;
}

/// Sorts finished downloads for the list.
List<DownloadState> sortDownloads(Iterable<DownloadState> items, DownloadSort sort) {
  final list = items.toList();
  switch (sort) {
    case DownloadSort.date:
      list.sort(
        (a, b) => (b.completedAt ?? b.createdAt ?? DateTime(0)).compareTo(a.completedAt ?? a.createdAt ?? DateTime(0)),
      );
    case DownloadSort.title:
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case DownloadSort.size:
      list.sort((a, b) => b.bytesTotal.compareTo(a.bytesTotal));
  }
  return list;
}

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  /// Keys of selected finished downloads; null when not selecting.
  Set<String>? _selected;

  void _toggle(String key) => setState(() {
    final selected = {...?_selected};
    selected.contains(key) ? selected.remove(key) : selected.add(key);
    _selected = selected.isEmpty ? null : selected;
  });

  Future<void> _deleteSelected() async {
    final keys = _selected?.toList() ?? const <String>[];
    if (keys.isEmpty) return;
    if (!await confirmRemoveDownloads(context, count: keys.length)) return;
    final manager = ref.read(downloadManagerProvider);
    for (final key in keys) {
      await manager.delete(key);
    }
    if (!mounted) return;
    setState(() => _selected = null);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).downloadsDeleted(keys.length))));
  }

  Future<void> _deleteFinished(List<DownloadState> complete) async {
    final l10n = AppLocalizations.of(context);
    final finished = complete.where((d) => d.finishedAt != null).toList();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (finished.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.downloadsNoneFinished)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.downloadsDeleteFinished),
        content: Text(l10n.downloadsDeleteFinishedBody(finished.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.genericCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l10n.genericRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final manager = ref.read(downloadManagerProvider);
    for (final d in finished) {
      await manager.delete(d.key);
    }
    messenger?.showSnackBar(SnackBar(content: Text(l10n.downloadsDeleted(finished.length))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final states = ref.watch(downloadStatesProvider);
    final sort = ref.watch(_sortProvider);
    final all = states.value?.values.toList() ?? const <DownloadState>[];
    final active = all.where((d) => d.isActive || d.phase == DownloadPhase.failed).toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    final complete = all.where((d) => d.isComplete).toList();
    final selecting = _selected != null;

    final appBar = selecting
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => setState(() => _selected = null),
            ),
            title: Text(l10n.downloadsSelectedCount(_selected!.length)),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: l10n.downloadsDeleteSelected(_selected!.length),
                onPressed: _deleteSelected,
              ),
            ],
          )
        : AppBar(
            title: Text(l10n.downloadsTitle),
            actions: [
              PopupMenuButton<DownloadSort>(
                icon: const Icon(Icons.sort_rounded),
                tooltip: l10n.downloadsSort,
                initialValue: sort,
                onSelected: ref.read(_sortProvider.notifier).set,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: DownloadSort.date,
                    checked: sort == DownloadSort.date,
                    child: Text(l10n.downloadsSortDate),
                  ),
                  CheckedPopupMenuItem(
                    value: DownloadSort.title,
                    checked: sort == DownloadSort.title,
                    child: Text(l10n.downloadsSortTitle),
                  ),
                  CheckedPopupMenuItem(
                    value: DownloadSort.size,
                    checked: sort == DownloadSort.size,
                    child: Text(l10n.downloadsSortSize),
                  ),
                ],
              ),
              PopupMenuButton<_Menu>(
                tooltip: l10n.downloadsMore,
                onSelected: (choice) => switch (choice) {
                  _Menu.select => setState(() => _selected = <String>{}),
                  _Menu.deleteFinished => unawaited(_deleteFinished(complete)),
                  _Menu.settings => unawaited(context.push(AppRoutes.downloadSettings)),
                },
                itemBuilder: (_) => [
                  if (complete.isNotEmpty) PopupMenuItem(value: _Menu.select, child: Text(l10n.downloadsSelect)),
                  if (complete.isNotEmpty)
                    PopupMenuItem(value: _Menu.deleteFinished, child: Text(l10n.downloadsDeleteFinished)),
                  PopupMenuItem(value: _Menu.settings, child: Text(l10n.downloadsSettings)),
                ],
              ),
            ],
          );

    final Widget body;
    if (states.isLoading && !states.hasValue) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (states.hasError && !states.hasValue) {
      body = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: ErrorNotice(message: l10n.genericSomethingWentWrong, details: '${states.error}'),
      );
    } else if (all.isEmpty) {
      body = ListView(
        children: [
          const SyncStatusTile(),
          EmptyState(
            icon: Icons.download_for_offline_outlined,
            title: l10n.downloadsEmpty,
            body: l10n.downloadsEmptyBody,
          ),
        ],
      );
    } else {
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _StorageBar(downloads: all)),
          const SliverToBoxAdapter(child: SyncStatusTile()),
          if (active.isNotEmpty) ...[
            SliverToBoxAdapter(child: _ActiveHeader(active: active)),
            SliverList.builder(
              itemCount: active.length,
              itemBuilder: (_, i) => _ActiveRow(state: active[i]),
            ),
          ],
          if (complete.isNotEmpty) ...[
            SliverToBoxAdapter(child: _SectionHeader(label: l10n.downloadsCompleted)),
            ..._groups(complete, sort),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
        ],
      );
    }
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) setState(() => _selected = null);
      },
      child: Scaffold(appBar: appBar, body: body),
    );
  }

  /// Finished downloads, one group per server when there are several.
  List<Widget> _groups(List<DownloadState> complete, DownloadSort sort) {
    final accounts = <String, String>{
      for (final a in ref.watch(accountsProvider).value ?? const <AccountRow>[]) a.id: a.displayName,
    };
    final byAccount = <String, List<DownloadState>>{};
    for (final d in complete) {
      byAccount.putIfAbsent((d.ref.source as AbsSource).accountId, () => []).add(d);
    }
    final ids = byAccount.keys.toList()..sort((a, b) => (accounts[a] ?? '').compareTo(accounts[b] ?? ''));
    final l10n = AppLocalizations.of(context);
    return [
      for (final id in ids) ...[
        if (ids.length > 1) SliverToBoxAdapter(child: _GroupHeader(label: accounts[id] ?? l10n.downloadsServerRemoved)),
        SliverList.list(
          children: [
            for (final d in sortDownloads(byAccount[id]!, sort))
              _CompleteRow(
                state: d,
                selected: _selected?.contains(d.key),
                onSelect: () => _toggle(d.key),
              ),
          ],
        ),
      ],
    ];
  }
}

enum _Menu { select, deleteFinished, settings }

/// This app's downloads against the free space on the phone.
class _StorageBar extends ConsumerWidget {
  const _StorageBar({required this.downloads});

  final List<DownloadState> downloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final used = downloads.fold<int>(0, (sum, d) => sum + (d.isComplete ? d.bytesTotal : d.bytesDone));
    final free = ref.watch(freeSpaceProvider).value;
    final usedText = formatBytes(l10n, used);
    final caption = free == null
        ? l10n.downloadsStorageUsedOnly(usedText)
        : l10n.downloadsStorageUsed(usedText, formatBytes(l10n, free));
    final share = free == null || used + free <= 0 ? 0.0 : used / (used + free);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      child: Semantics(
        label: caption,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: scheme.surfaceContainerHighest)),
                    FractionallySizedBox(
                      widthFactor: free == null ? 0 : share.clamp(0.01, 1.0),
                      child: ColoredBox(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(caption, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.sm, Space.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xs),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _ActiveHeader extends ConsumerWidget {
  const _ActiveHeader({required this.active});
  final List<DownloadState> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final manager = ref.read(downloadManagerProvider);
    final running = active.any((d) => d.isActive && d.phase != DownloadPhase.paused);
    final paused = active.any((d) => d.phase == DownloadPhase.paused);
    final failed = active.any((d) => d.phase == DownloadPhase.failed);
    return _SectionHeader(
      label: l10n.downloadsActive,
      trailing: Wrap(
        children: [
          if (failed) TextButton(onPressed: manager.retryFailed, child: Text(l10n.downloadsRetryAll)),
          if (running)
            TextButton(onPressed: manager.pauseAll, child: Text(l10n.downloadsPauseAll))
          else if (paused)
            TextButton(onPressed: manager.resumeAll, child: Text(l10n.downloadsResumeAll)),
        ],
      ),
    );
  }
}

/// The cover saved with a download, or the placeholder.
class _DownloadCover extends ConsumerWidget {
  const _DownloadCover({required this.state});
  final DownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(supportPathProvider).value;
    final cover = state.coverPath;
    return CoverImage(
      source: support == null || cover == null ? null : FileCover(p.join(support, cover)),
      title: state.title,
      size: 52,
      radius: Radii.cover / 1.5,
    );
  }
}

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.state});
  final DownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final failed = state.phase == DownloadPhase.failed;
    final phaseText = switch (state.phase) {
      DownloadPhase.queued => l10n.downloadQueued,
      DownloadPhase.waitingForWifi => l10n.downloadWaitingWifi,
      DownloadPhase.paused => l10n.downloadPaused,
      DownloadPhase.failed => downloadErrorText(l10n, state.error),
      _ => null,
    };
    final bytes = state.bytesTotal > 0
        ? l10n.downloadsBytesOf(formatBytes(l10n, state.bytesDone), formatBytes(l10n, state.bytesTotal))
        : null;
    return InkWell(
      onLongPress: () => unawaited(showDownloadOptions(context, ref, state, title: state.title)),
      onTap: () => unawaited(showDownloadOptions(context, ref, state, title: state.title)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
        child: Row(
          children: [
            _DownloadCover(state: state),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: Space.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: state.fraction,
                      minHeight: 4,
                      color: failed ? scheme.error : scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    [?bytes, ?phaseText].join('  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: failed ? scheme.error : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            DownloadButton(itemRef: state.ref, title: state.title, compact: true),
          ],
        ),
      ),
    );
  }
}

class _CompleteRow extends ConsumerWidget {
  const _CompleteRow({required this.state, required this.selected, required this.onSelect});

  final DownloadState state;

  /// Null when not selecting.
  final bool? selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selecting = selected != null;
    final subtitle = [?state.author, formatBytes(l10n, state.bytesTotal)].join('  ');
    return InkWell(
      onLongPress: selecting ? null : onSelect,
      onTap: () {
        if (selecting) return onSelect();
        final current = ref.read(currentAccountProvider).value?.id;
        final accountId = (state.ref.source as AbsSource).accountId;
        if (current == accountId && state.ref.episodeId == null) {
          unawaited(context.push(AppRoutes.item(state.ref.itemId)));
        } else {
          unawaited(ref.read(playerEngineProvider).playItem(state.ref));
        }
      },
      child: Container(
        color: selected == true ? scheme.secondaryContainer.withValues(alpha: 0.5) : null,
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Checkbox(value: selected, onChanged: (_) => onSelect()),
              ),
            _DownloadCover(state: state),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!selecting)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: l10n.downloadsMore,
                onPressed: () => unawaited(showDownloadOptions(context, ref, state, title: state.title)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Downloads row on the You tab.
class DownloadsEntryTile extends ConsumerWidget {
  const DownloadsEntryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(downloadStatesProvider).value?.values ?? const <DownloadState>[];
    final active = all.where((d) => d.isActive).length;
    final complete = all.where((d) => d.isComplete).length;
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l10n.downloadsTitle),
      subtitle: Text(active > 0 ? l10n.downloadsActiveCount(active) : l10n.downloadsCountOnPhone(complete)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(AppRoutes.downloads),
    );
  }
}
