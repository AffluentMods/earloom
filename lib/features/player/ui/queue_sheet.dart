// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.95,
    builder: (context, scroll) => QueueSheet(controller: scroll),
  ),
);

/// Up next: what plays after this book. Drag to reorder, swipe to remove.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key, this.controller});
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final engine = ref.read(playerEngineProvider);
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.sm, Space.sm),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: Text(l10n.playerQueue, style: theme.textTheme.titleLarge)),
                if (queue.isNotEmpty) TextButton(onPressed: engine.clearQueue, child: Text(l10n.queueClear)),
              ],
            ),
          ),
        ),
        if (queue.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.queue_music_rounded, title: l10n.playerQueue, body: l10n.queueEmpty),
          )
        else
          SliverReorderableList(
            itemCount: queue.length,
            onReorderItem: engine.moveInQueue,
            itemBuilder: (context, i) {
              final e = queue[i];
              return Dismissible(
                key: ValueKey(e.ref.key),
                direction: DismissDirection.endToStart,
                background: ColoredBox(color: scheme.errorContainer),
                onDismissed: (_) => engine.removeFromQueue(e.ref),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: Space.xl, end: Space.sm),
                    leading: CoverImage(source: e.cover, title: e.title, size: 48, radius: 8),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: e.author == null ? null : Text(e.author!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.queueRemove,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          onPressed: () => engine.removeFromQueue(e.ref),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(Space.sm),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(child: SizedBox(height: Space.xl + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}
