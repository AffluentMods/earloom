// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/offline_providers.dart';

/// A quiet line at the top of the tabs while the current server does not
/// answer (docs/plan/05-phase4-offline.md 4.8). Offline is a state, not an
/// error: downloaded books still play and screens show what is cached.
///
/// Wraps [child]: while the banner shows it takes the status bar inset, so
/// the screen below does not pad for it twice.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final banner = AnimatedSize(
      duration: Motion.normal,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Semantics(
              key: const ValueKey('offlineBanner'),
              liveRegion: true,
              child: Material(
                color: scheme.surfaceContainerHighest,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.sm, Space.xs),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            l10n.offlineBanner,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(ref.read(syncSchedulerProvider).onForeground()),
                          child: Text(l10n.offlineBannerCheck),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
    return Column(
      children: [
        banner,
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: offline, child: child),
        ),
      ],
    );
  }
}
