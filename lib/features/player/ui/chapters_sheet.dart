// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import 'player_widgets.dart';

Future<void> showChaptersSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, scroll) => ChaptersSheet(controller: scroll),
  ),
);

/// Every chapter with its start and length. The current one is marked and
/// scrolled into view; finished ones are dimmed.
class ChaptersSheet extends ConsumerStatefulWidget {
  const ChaptersSheet({super.key, this.controller});
  final ScrollController? controller;

  @override
  ConsumerState<ChaptersSheet> createState() => _ChaptersSheetState();
}

class _ChaptersSheetState extends ConsumerState<ChaptersSheet> {
  static const _rowHeight = 64.0;
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chapters = ref.watch(playerProvider.select((s) => s.now?.chapters ?? const []));
    final current = ref.watch(playerProvider.select((s) => s.chapterIndex));
    final speed = ref.watch(playerProvider.select((s) => s.speed));
    if (!_scrolled && widget.controller != null && chapters.isNotEmpty) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = widget.controller!;
        if (!c.hasClients) return;
        final target = (current - 2).clamp(0, chapters.length) * _rowHeight;
        c.jumpTo(target.clamp(0, c.position.maxScrollExtent));
      });
    }
    return CustomScrollView(
      controller: widget.controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
          sliver: SliverToBoxAdapter(child: Text(l10n.playerChapters, style: theme.textTheme.titleLarge)),
        ),
        SliverFixedExtentList.builder(
          itemExtent: _rowHeight,
          itemCount: chapters.length,
          itemBuilder: (context, i) {
            final c = chapters[i];
            final isCurrent = i == current;
            final done = i < current;
            final muted = done ? scheme.onSurfaceVariant : scheme.onSurface;
            return ListTile(
              selected: isCurrent,
              selectedTileColor: scheme.secondaryContainer,
              selectedColor: scheme.onSecondaryContainer,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              leading: SizedBox(
                width: 28,
                child: isCurrent
                    ? Icon(Icons.graphic_eq_rounded, color: scheme.onSecondaryContainer)
                    : Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              title: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isCurrent ? scheme.onSecondaryContainer : muted,
                  fontWeight: isCurrent ? FontWeight.w600 : null,
                ),
              ),
              subtitle: Text(
                formatClock(c.start),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isCurrent ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              trailing: Text(
                formatClock(atSpeed(c.duration, speed)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isCurrent ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              onTap: () {
                ref.read(playerEngineProvider).seek(c.start);
                Navigator.of(context).pop();
              },
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
      ],
    );
  }
}
