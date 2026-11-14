// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../core/net/abs_errors.dart';
import '../../core/ui/states.dart';
import '../../features/library/ui/widgets/browse_layout.dart';
import '../../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';

/// Every shared state in one place for design review
/// (docs/plan/09-phase8-settings-polish.md 8.3): loading, empty, offline
/// with and without cache, server error, sign in again, and the notices.
class StatesCatalogScreen extends StatelessWidget {
  const StatesCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: Space.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Padding(padding: const EdgeInsets.all(Space.md), child: child),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('States')),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          section(
            'Loading (skeleton shaped like the content)',
            const Row(
              children: [
                SkeletonBox(width: 96, height: 96, radius: Radii.cover),
                SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 14),
                      SizedBox(height: Space.sm),
                      SkeletonBox(width: 100, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          section(
            'Empty',
            EmptyState(
              icon: Icons.library_books_outlined,
              title: l10n.libraryEmptyLocal,
              body: l10n.libraryEmptyLocalBody,
              action: FilledButton(onPressed: () {}, child: Text(l10n.homeWelcomeTitle)),
            ),
          ),
          section('Offline with cache', const RefreshNotice(error: AbsUnreachable('connectionError'))),
          section(
            'Offline without cache',
            EmptyState(icon: Icons.cloud_off_rounded, title: l10n.offlineBanner, body: l10n.probeUnreachable),
          ),
          section(
            'Server error (refresh failed, content kept)',
            const RefreshNotice(error: AbsHttpError(500, 'HTTP 500 Internal Server Error')),
          ),
          section(
            'Error with details to copy',
            ErrorNotice(
              message: l10n.genericSomethingWentWrong,
              details: 'HTTP 502 Bad Gateway at /api/items',
              action: FilledButton.tonal(onPressed: () {}, child: Text(l10n.genericRetry)),
            ),
          ),
          section(
            'Signed out (sign in again)',
            InlineNotice(icon: Icons.lock_clock_outlined, message: l10n.sessionExpiredBanner, tone: NoticeTone.warning),
          ),
          section('Info notice', InlineNotice(icon: Icons.info_outline_rounded, message: l10n.offlineBanner)),
        ],
      ),
    );
  }
}
