// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_errors.dart';
import '../../library/ui/widgets/browse_layout.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/data/abs_json.dart';
import '../../../core/ui/html_text.dart';
import '../data/podcast_json.dart';
import '../data/podcast_models.dart';
import '../data/podcast_providers.dart';
import '../data/podcast_repository.dart';

// Server-side podcast actions (docs/plan/06-phase5-podcasts.md 5.5). Only
// shown to users the server allows: admins and root for checking and
// downloading on the server, the update permission for editing the feed
// (docs/abs-api.md section 13). Every action asks first and reports what
// the server said.

/// Shows an admin action's failure in plain words, with the server's own
/// message when it sent one, and Copy details.
void showAdminError(BuildContext context, Object error) =>
    showActionError(context, error, message: adminErrorText(AppLocalizations.of(context), error));

/// The plain words for an admin action's failure.
String adminErrorText(AppLocalizations l10n, Object error) {
  final said = serverMessage(error);
  if (error is AbsForbidden) return l10n.podcastAdminForbidden;
  if (error is AbsUnreachable) return l10n.offlineBanner;
  if (said != null) return l10n.podcastAdminServerSaid(said);
  return l10n.genericActionFailed;
}

/// Asks before an admin action. True when the user confirmed.
Future<bool> confirmAdminAction(BuildContext context, {required String title, required String body}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.genericCancel)),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(l10n.podcastAdminConfirm)),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs [task] behind a small "working" dialog, so a slow server call
/// cannot be started twice.
Future<T> withProgress<T>(BuildContext context, Future<T> Function() task) async {
  final l10n = AppLocalizations.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: Space.lg),
              Expanded(child: Text(l10n.podcastAdminWorking)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

/// The admin actions of one show, as a sheet.
Future<void> showShowAdminActions(BuildContext context, WidgetRef ref, ShowDetail detail, UserAccess access) async {
  final l10n = AppLocalizations.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(l10n.podcastAdminActions, style: Theme.of(sheet).textTheme.titleLarge),
          ),
          if (access.isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(l10n.podcastAdminCheckNew),
              subtitle: Text(l10n.podcastAdminCheckNewBody),
              onTap: () => Navigator.pop(sheet, 'check'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(l10n.podcastAdminDownloadToServer),
              subtitle: Text(l10n.podcastAdminDownloadToServerBody),
              onTap: () => Navigator.pop(sheet, 'download'),
            ),
          ],
          if (access.canUpdate || access.isAdmin)
            ListTile(
              leading: const Icon(Icons.rss_feed_rounded),
              title: Text(l10n.podcastAdminEditFeed),
              subtitle: Text(l10n.podcastAdminEditFeedBody),
              onTap: () => Navigator.pop(sheet, 'edit'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'check':
      await checkNewEpisodes(context, ref, detail);
    case 'download':
      await downloadEpisodesToServer(context, ref, detail);
    case 'edit':
      await editFeed(context, ref, detail);
  }
}

Future<void> checkNewEpisodes(BuildContext context, WidgetRef ref, ShowDetail detail) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(podcastRepositoryProvider);
  if (repository == null) return;
  if (detail.feedUrl == null) {
    showMessage(context, l10n.podcastAdminNoFeed);
    return;
  }
  final ok = await confirmAdminAction(
    context,
    title: l10n.podcastAdminCheckNew,
    body: l10n.podcastAdminCheckNewConfirm(detail.show.title),
  );
  if (!ok || !context.mounted) return;
  final itemId = detail.show.ref.itemId;
  try {
    final found = await withProgress(context, () => repository.checkNewEpisodes(itemId));
    if (context.mounted) {
      showMessage(context, found.isEmpty ? l10n.podcastAdminNoNew : l10n.podcastAdminFoundNew(found.length));
    }
    // The server downloads them in the background; the socket brings them
    // in as they land. A refresh shows what is already there.
    unawaited(repository.refreshShow(itemId, force: true).catchError((Object _) {}));
  } on Object catch (e) {
    if (context.mounted) showAdminError(context, e);
  }
}

Future<void> downloadEpisodesToServer(BuildContext context, WidgetRef ref, ShowDetail detail) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(podcastRepositoryProvider);
  final feed = detail.feedUrl;
  if (repository == null) return;
  if (feed == null) {
    showMessage(context, l10n.podcastAdminNoFeed);
    return;
  }
  final itemId = detail.show.ref.itemId;
  final List<Map<String, Object?>> missing;
  try {
    missing = await withProgress(context, () => repository.feedEpisodesNotOnServer(itemId, feed));
  } on Object catch (e) {
    if (context.mounted) showAdminError(context, e);
    return;
  }
  if (!context.mounted) return;
  if (missing.isEmpty) {
    showMessage(context, l10n.podcastAdminAllOnServer);
    return;
  }
  final chosen = await showModalBottomSheet<List<Map<String, Object?>>>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _FeedEpisodePicker(episodes: missing),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  final ok = await confirmAdminAction(
    context,
    title: l10n.podcastAdminDownloadToServer,
    body: l10n.podcastAdminDownloadConfirm(chosen.length, detail.show.title),
  );
  if (!ok || !context.mounted) return;
  try {
    await withProgress(context, () => repository.downloadToServer(itemId, chosen));
    if (context.mounted) showMessage(context, l10n.podcastAdminDownloadQueued(chosen.length));
  } on Object catch (e) {
    if (context.mounted) showAdminError(context, e);
  }
}

class _FeedEpisodePicker extends StatefulWidget {
  const _FeedEpisodePicker({required this.episodes});

  final List<Map<String, Object?>> episodes;

  @override
  State<_FeedEpisodePicker> createState() => _FeedEpisodePickerState();
}

class _FeedEpisodePickerState extends State<_FeedEpisodePicker> {
  final _chosen = <int>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Row(
              children: [
                Expanded(child: Text(l10n.podcastAdminPickEpisodes, style: theme.textTheme.titleLarge)),
                TextButton(
                  onPressed: () => setState(() {
                    if (_chosen.length == widget.episodes.length) {
                      _chosen.clear();
                    } else {
                      _chosen.addAll(List.generate(widget.episodes.length, (i) => i));
                    }
                  }),
                  child: Text(
                    _chosen.length == widget.episodes.length ? l10n.podcastAdminSelectNone : l10n.podcastAdminSelectAll,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: widget.episodes.length,
              itemBuilder: (context, i) {
                final e = widget.episodes[i];
                final date = AbsJson.str(e['pubDate']);
                return CheckboxListTile(
                  value: _chosen.contains(i),
                  onChanged: (v) => setState(() => v == true ? _chosen.add(i) : _chosen.remove(i)),
                  title: Text(AbsJson.str(e['title']) ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: date == null ? null : Text(date, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: FilledButton.icon(
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, [for (final i in _chosen.toList()..sort()) widget.episodes[i]]),
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(l10n.podcastAdminDownloadCount(_chosen.length)),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> editFeed(BuildContext context, WidgetRef ref, ShowDetail detail) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(podcastRepositoryProvider);
  if (repository == null) return;
  final result = await showDialog<({String feed, bool auto, String schedule})>(
    context: context,
    builder: (_) => _EditFeedDialog(detail: detail),
  );
  if (result == null || !context.mounted) return;
  try {
    await withProgress(
      context,
      () => repository.editFeed(
        detail.show.ref.itemId,
        feedUrl: result.feed,
        autoDownload: result.auto,
        schedule: result.schedule.isEmpty ? null : result.schedule,
      ),
    );
    if (context.mounted) showMessage(context, l10n.podcastAdminSaved);
  } on Object catch (e) {
    if (context.mounted) showAdminError(context, e);
  }
}

class _EditFeedDialog extends StatefulWidget {
  const _EditFeedDialog({required this.detail});

  final ShowDetail detail;

  @override
  State<_EditFeedDialog> createState() => _EditFeedDialogState();
}

class _EditFeedDialogState extends State<_EditFeedDialog> {
  late final _feed = TextEditingController(text: widget.detail.feedUrl ?? '');
  late final _schedule = TextEditingController(text: widget.detail.serverAutoDownloadSchedule ?? '');
  late bool _auto = widget.detail.serverAutoDownload;

  @override
  void dispose() {
    _feed.dispose();
    _schedule.dispose();
    super.dispose();
  }

  bool get _valid {
    final uri = Uri.tryParse(_feed.text.trim());
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.podcastAdminEditFeed),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _feed,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.podcastAdminFeedUrl,
              errorText: _feed.text.trim().isEmpty || _valid ? null : l10n.podcastAdminFeedInvalid,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.podcastAdminServerAutoDownload),
            value: _auto,
            onChanged: (v) => setState(() => _auto = v),
          ),
          if (_auto)
            TextField(
              controller: _schedule,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.podcastAdminSchedule,
                helperText: l10n.podcastAdminScheduleHint,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.genericCancel)),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, (feed: _feed.text.trim(), auto: _auto, schedule: _schedule.text.trim()))
              : null,
          child: Text(l10n.genericSave),
        ),
      ],
    );
  }
}

/// A plain-words summary of a feed preview, for the add flow.
class FeedPreviewCard extends StatelessWidget {
  const FeedPreviewCard({super.key, required this.preview});

  final FeedPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.title, style: theme.textTheme.titleLarge),
            if (preview.author != null) ...[
              const SizedBox(height: Space.xs),
              Text(preview.author!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (preview.episodes.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(
                l10n.podcastEpisodes(preview.episodes.length),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (preview.description != null && preview.description!.trim().isNotEmpty) ...[
              const SizedBox(height: Space.md),
              DescriptionText(html: preview.description!, maxLines: 4, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Space.md),
            Text(
              preview.feedUrl,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a show after it was added.
ItemRef showRefOf(AbsPodcastRepository repository, String itemId) => ItemRef(repository.source, itemId);
