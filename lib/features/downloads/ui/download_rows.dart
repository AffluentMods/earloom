// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/ui/widgets/browse_layout.dart' show CopyDetailsButton;
import '../data/download_manager.dart';
import '../data/offline_providers.dart';
import 'download_button.dart';

// A download that is not finished, with its controls as labeled buttons:
// pause or resume, try again, cancel. They sit wherever the download shows
// (the book screen, Listen, Downloads), so stopping one never means going
// looking for it.

/// The cover saved with a download, or the placeholder.
class DownloadCover extends ConsumerWidget {
  const DownloadCover({super.key, required this.state, this.size = 52});

  final DownloadState state;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(supportPathProvider).value;
    final cover = state.coverPath;
    return CoverImage(
      source: support == null || cover == null ? null : FileCover(p.join(support, cover)),
      title: state.title,
      size: size,
      radius: Radii.cover / 1.5,
    );
  }
}

/// What a download is doing, in words: "Downloading, 45%", "Paused at
/// 45%", "Queued", "Waiting for Wi-Fi", or what went wrong.
String downloadStatusText(AppLocalizations l10n, DownloadState state) {
  final percent = (state.fraction * 100).floor();
  return switch (state.phase) {
    DownloadPhase.downloading => l10n.downloadDownloadingPercent(percent),
    DownloadPhase.paused => l10n.downloadPausedPercent(percent),
    DownloadPhase.queued => l10n.downloadQueued,
    DownloadPhase.waitingForWifi => l10n.downloadWaitingWifi,
    DownloadPhase.failed => downloadErrorText(l10n, state.error),
    DownloadPhase.complete => l10n.downloadDownloaded,
    DownloadPhase.none => '',
  };
}

/// The status line, a progress bar and the buttons of one unfinished
/// download.
class DownloadControls extends ConsumerWidget {
  const DownloadControls({super.key, required this.state, this.showBytes = true});

  final DownloadState state;

  /// Adds "12 MB of 300 MB" to the status line.
  final bool showBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final manager = ref.read(downloadManagerProvider);
    final failed = state.phase == DownloadPhase.failed;
    final bytes = showBytes && state.bytesTotal > 0 && !failed
        ? l10n.downloadsBytesOf(formatBytes(l10n, state.bytesDone), formatBytes(l10n, state.bytesTotal))
        : null;
    final status = [downloadStatusText(l10n, state), ?bytes].join('  ');
    void run(Future<void> Function() action) => unawaited(action());
    final details = state.errorDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: failed ? scheme.error : scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            switch (state.phase) {
              DownloadPhase.downloading => OutlinedButton.icon(
                onPressed: () => run(() => manager.pause(state.key)),
                icon: const Icon(Icons.pause_rounded),
                label: Text(l10n.downloadPause),
              ),
              DownloadPhase.paused => FilledButton.tonalIcon(
                onPressed: () => run(() => manager.resume(state.key)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.downloadResume),
              ),
              DownloadPhase.failed => FilledButton.tonalIcon(
                onPressed: () => run(() => manager.resume(state.key)),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.downloadRetry),
              ),
              _ => const SizedBox.shrink(),
            },
            TextButton.icon(
              onPressed: () => run(() => manager.cancel(state.key)),
              icon: const Icon(Icons.close_rounded),
              label: Text(l10n.downloadCancel),
            ),
            if (failed && details != null && details.isNotEmpty) CopyDetailsButton(details: details),
          ],
        ),
      ],
    );
  }
}

/// An unfinished download as a row: cover, title, then [DownloadControls].
class ActiveDownloadRow extends StatelessWidget {
  const ActiveDownloadRow({super.key, required this.state, this.onTap});

  final DownloadState state;

  /// Opens the book. Null leaves the row without a tap action.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DownloadCover(state: state),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: Space.sm),
                  DownloadControls(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The download of one book while it is not finished, on the book's own
/// screen. Draws nothing when there is no download or it is complete.
class DownloadProgressPanel extends ConsumerWidget {
  const DownloadProgressPanel({super.key, required this.itemRef});

  final ItemRef itemRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemRef.source is! AbsSource) return const SizedBox.shrink();
    final state = ref.watch(downloadStateProvider(itemRef));
    final show = state.phase != DownloadPhase.none && state.phase != DownloadPhase.complete;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: Motion.normal,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: Space.lg),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Space.lg),
                ),
                child: DownloadControls(state: state),
              ),
            ),
    );
  }
}
