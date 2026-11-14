// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../bookmarks.dart';
import '../chapters.dart';
import '../player_controller.dart';
import 'player_widgets.dart';

Future<void> showBookmarksSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.95,
    builder: (context, scroll) => BookmarksSheet(controller: scroll),
  ),
);

/// Adds a bookmark where the player is, with haptics and a snackbar that
/// offers to add a note. Used by Now Playing and the notification button.
Future<void> addBookmarkHere(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final s = ref.read(playerProvider);
  final now = s.now;
  if (now == null) return;
  final chapter = s.chapter;
  final title = chapter == null
      ? formatClock(s.position)
      : l10n.bookmarkDefaultTitle(chapter.title, formatClock(s.position - chapter.start));
  await HapticFeedback.mediumImpact();
  try {
    final at = await ref.read(bookmarkServiceProvider).add(now.ref, s.position, title);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.bookmarkAdded),
          action: SnackBarAction(
            label: l10n.bookmarkAddNote,
            onPressed: () {
              if (context.mounted) unawaited(editBookmark(context, ref, now.ref, at, title));
            },
          ),
        ),
      );
  } on Object catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.bookmarkFailed),
        action: SnackBarAction(
          label: l10n.genericCopyDetails,
          onPressed: () => Clipboard.setData(ClipboardData(text: '$e')),
        ),
      ),
    );
  }
}

Future<void> editBookmark(BuildContext context, WidgetRef ref, ItemRef item, Duration at, String current) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: current);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.bookmarkEdit),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.bookmarkTitleField),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.genericCancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: Text(l10n.genericSave)),
      ],
    ),
  );
  if (title == null || title.isEmpty || title == current) return;
  await ref.read(bookmarkServiceProvider).rename(item, at, title);
}

class BookmarksSheet extends ConsumerWidget {
  const BookmarksSheet({super.key, this.controller});
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(playerProvider.select((s) => s.now));
    if (now == null) return const SizedBox.shrink();
    final bookmarks = ref.watch(bookmarksProvider(now.ref));
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.sm, Space.sm),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: Text(l10n.playerBookmarks, style: theme.textTheme.titleLarge)),
                TextButton.icon(
                  onPressed: () => addBookmarkHere(context, ref),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.playerBookmark),
                ),
              ],
            ),
          ),
        ),
        switch (bookmarks) {
          AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.bookmarks_outlined, title: l10n.playerBookmarks, body: l10n.bookmarksEmpty),
          ),
          AsyncData(:final value) => SliverList.builder(
            itemCount: value.length,
            itemBuilder: (context, i) => _BookmarkTile(bookmark: value[i], chapters: now.chapters),
          ),
          AsyncError(:final error) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: ErrorNotice(message: l10n.genericSomethingWentWrong, details: '$error'),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Space.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        },
        SliverToBoxAdapter(child: SizedBox(height: Space.xl + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

class _BookmarkTile extends ConsumerWidget {
  const _BookmarkTile({required this.bookmark, required this.chapters});
  final Bookmark bookmark;
  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chapter = chapters.isEmpty ? null : chapters[chapterIndexAt(chapters, bookmark.position)];
    return Dismissible(
      key: ValueKey(bookmark.position),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: Space.xl),
            child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
          ),
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        await ref.read(bookmarkServiceProvider).delete(bookmark.ref, bookmark.position);
        messenger.showSnackBar(SnackBar(content: Text(l10n.bookmarkDeleted)));
      },
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(start: Space.xl, end: Space.xs),
        leading: Icon(Icons.bookmark_rounded, color: scheme.primary),
        title: Text(bookmark.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [formatClock(bookmark.position), ?chapter?.title].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: l10n.playerMore,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(l10n.bookmarkEdit)),
            PopupMenuItem(value: 'delete', child: Text(l10n.bookmarkDelete)),
          ],
          onSelected: (action) async {
            if (action == 'edit') {
              await editBookmark(context, ref, bookmark.ref, bookmark.position, bookmark.title);
            } else {
              await ref.read(bookmarkServiceProvider).delete(bookmark.ref, bookmark.position);
            }
          },
        ),
        onTap: () {
          ref.read(playerEngineProvider).seek(bookmark.position);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
