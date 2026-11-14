// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/download_manager.dart';
import '../data/offline_providers.dart';

/// The download control for one book or episode, in every state of
/// docs/plan/05-phase4-offline.md 4.4:
///
/// | State | Shows | Tap |
/// |---|---|---|
/// | none | Download | starts the download |
/// | waiting for Wi-Fi | Waiting for Wi-Fi | options (cancel) |
/// | queued | Queued | options (cancel) |
/// | downloading | progress ring and percent | pauses |
/// | paused | Paused | resumes |
/// | failed | Download failed | tries again |
/// | downloaded | Downloaded | options (remove, download again) |
///
/// A long press opens the options in every state but "none", including the
/// error details of a failed download.
///
/// ```dart
/// DownloadButton(itemRef: ref, title: book.title)               // pill
/// DownloadButton(itemRef: ref, title: book.title, compact: true) // icon
/// ```
///
/// [itemRef] is any item; books from the On this device library are always
/// on the phone, so the button draws nothing for them. [title] names the
/// book in the list and the notification until the server's details
/// arrive. [compact] draws a 48 dp icon button for rows and app bars.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({super.key, required this.itemRef, required this.title, this.compact = false});

  final ItemRef itemRef;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemRef.source is! AbsSource) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(downloadStateProvider(itemRef));
    final percent = (state.fraction * 100).floor();
    final label = switch (state.phase) {
      DownloadPhase.none => l10n.downloadAction,
      DownloadPhase.queued => l10n.downloadQueued,
      DownloadPhase.waitingForWifi => l10n.downloadWaitingWifi,
      DownloadPhase.downloading => l10n.downloadProgress(percent),
      DownloadPhase.paused => l10n.downloadPaused,
      DownloadPhase.failed => l10n.downloadFailed,
      DownloadPhase.complete => l10n.downloadDownloaded,
    };
    final semantics = state.phase == DownloadPhase.downloading ? l10n.downloadProgressSemantics(percent) : label;
    void onTap() => unawaited(_tap(context, ref, state));
    void onLongPress() {
      if (state.phase == DownloadPhase.none) return;
      unawaited(showDownloadOptions(context, ref, state, title: title));
    }

    final leading = _StateIcon(state: state, size: compact ? 26 : 20);
    if (compact) {
      return Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: InkResponse(
            onTap: onTap,
            onLongPress: onLongPress,
            radius: 24,
            child: SizedBox.square(dimension: 48, child: Center(child: leading)),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final failed = state.phase == DownloadPhase.failed;
    final (background, foreground) = failed
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : state.isComplete
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leading,
                    const SizedBox(width: Space.sm),
                    AnimatedSwitcher(
                      duration: Motion.fast,
                      child: Text(
                        label,
                        key: ValueKey(state.phase),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref, DownloadState state) async {
    final manager = ref.read(downloadManagerProvider);
    switch (state.phase) {
      case DownloadPhase.none:
        final messenger = ScaffoldMessenger.maybeOf(context);
        final text = AppLocalizations.of(context).downloadQueuedSnack;
        unawaited(HapticFeedback.lightImpact());
        await manager.enqueueItem(itemRef, title: title);
        messenger?.showSnackBar(SnackBar(content: Text(text)));
      case DownloadPhase.downloading:
        await manager.pause(state.key);
      case DownloadPhase.paused:
        await manager.resume(state.key);
      case DownloadPhase.failed:
        await manager.resume(state.key);
      case DownloadPhase.queued || DownloadPhase.waitingForWifi || DownloadPhase.complete:
        if (context.mounted) await showDownloadOptions(context, ref, state, title: title);
    }
  }
}

/// The icon (or progress ring) for a download state.
class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state, required this.size});

  final DownloadState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child = switch (state.phase) {
      DownloadPhase.downloading => SizedBox.square(
        key: const ValueKey('ring'),
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: state.fraction),
              duration: Motion.normal,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: size > 22 ? 3 : 2.5,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                color: scheme.primary,
              ),
            ),
            Icon(Icons.pause_rounded, size: size * 0.55),
          ],
        ),
      ),
      DownloadPhase.queued => Icon(Icons.schedule_rounded, key: const ValueKey('queued'), size: size),
      DownloadPhase.waitingForWifi => Icon(Icons.wifi_off_rounded, key: const ValueKey('wifi'), size: size),
      DownloadPhase.paused => Icon(Icons.play_arrow_rounded, key: const ValueKey('paused'), size: size),
      DownloadPhase.failed => Icon(
        Icons.error_outline_rounded,
        key: const ValueKey('failed'),
        size: size,
        color: scheme.error,
      ),
      DownloadPhase.complete => Icon(Icons.download_done_rounded, key: const ValueKey('done'), size: size),
      DownloadPhase.none => Icon(Icons.download_rounded, key: const ValueKey('none'), size: size),
    };
    return AnimatedSwitcher(duration: Motion.fast, child: child);
  }
}

/// A small mark for covers and rows: the book is on this phone.
class DownloadedBadge extends ConsumerWidget {
  const DownloadedBadge({super.key, required this.itemRef, this.size = 20});

  final ItemRef itemRef;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemRef.source is! AbsSource) return const SizedBox.shrink();
    final complete = ref.watch(downloadStateProvider(itemRef).select((s) => s.isComplete));
    if (!complete) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: AppLocalizations.of(context).downloadDownloaded,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 1.5),
        ),
        child: Icon(Icons.download_done_rounded, size: size * 0.66, color: scheme.onPrimary),
      ),
    );
  }
}

/// Plain words for a download error.
String downloadErrorText(AppLocalizations l10n, DownloadError? error) => switch (error) {
  DownloadError.incomplete => l10n.downloadFileIncomplete,
  DownloadError.network => l10n.downloadErrorNetwork,
  DownloadError.forbidden => l10n.downloadErrorForbidden,
  DownloadError.notFound => l10n.downloadErrorNotFound,
  DownloadError.storage => l10n.downloadErrorStorage,
  DownloadError.auth => l10n.downloadErrorAuth,
  DownloadError.other || null => l10n.downloadErrorOther,
};

/// What can be done with a download: pause, resume, cancel, try again,
/// remove, download again. Failed downloads show the error with "Copy
/// details".
Future<void> showDownloadOptions(
  BuildContext context,
  WidgetRef ref,
  DownloadState state, {
  required String title,
}) {
  final manager = ref.read(downloadManagerProvider);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) {
      final l10n = AppLocalizations.of(sheet);
      final text = Theme.of(sheet).textTheme;
      Widget action(IconData icon, String label, Future<void> Function() run, {bool destructive = false}) {
        final color = destructive ? Theme.of(sheet).colorScheme.error : null;
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () async {
            Navigator.pop(sheet);
            await run();
          },
        );
      }

      Future<void> remove() async {
        if (await confirmRemoveDownloads(context, count: 1)) await manager.delete(state.key);
      }

      final shown = state.title.isEmpty ? title : state.title;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Text(shown, style: text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (state.phase == DownloadPhase.failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                child: ErrorNotice(message: downloadErrorText(l10n, state.error), details: state.errorDetails),
              ),
            ...switch (state.phase) {
              DownloadPhase.complete => [
                action(Icons.refresh_rounded, l10n.downloadRedownload, () async {
                  await manager.delete(state.key);
                  await manager.enqueueItem(state.ref, title: shown);
                }),
                action(Icons.delete_outline_rounded, l10n.downloadDelete, remove, destructive: true),
              ],
              DownloadPhase.failed => [
                action(Icons.refresh_rounded, l10n.downloadRetry, () => manager.resume(state.key)),
                action(Icons.delete_outline_rounded, l10n.downloadDelete, remove, destructive: true),
              ],
              DownloadPhase.paused => [
                action(Icons.play_arrow_rounded, l10n.downloadResume, () => manager.resume(state.key)),
                action(Icons.close_rounded, l10n.downloadCancel, () => manager.cancel(state.key), destructive: true),
              ],
              DownloadPhase.queued || DownloadPhase.waitingForWifi || DownloadPhase.downloading => [
                action(Icons.pause_rounded, l10n.downloadPause, () => manager.pause(state.key)),
                action(Icons.close_rounded, l10n.downloadCancel, () => manager.cancel(state.key), destructive: true),
              ],
              DownloadPhase.none => const <Widget>[],
            },
            const SizedBox(height: Space.sm),
          ],
        ),
      );
    },
  );
}

/// Asks before removing downloaded files. Progress and bookmarks stay.
Future<bool> confirmRemoveDownloads(BuildContext context, {required int count}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(count == 1 ? l10n.downloadDeleteConfirmTitle : l10n.downloadsDeleteSelected(count)),
      content: Text(l10n.downloadDeleteConfirmBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.genericCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(l10n.genericRemove),
        ),
      ],
    ),
  );
  if (ok == true) await HapticFeedback.heavyImpact();
  return ok == true;
}
