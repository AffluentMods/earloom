// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/debug/debug_routes.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../downloads/ui/downloads_screen.dart' show DownloadsEntryTile;

/// The You tab: servers, files on this phone, and (in later phases)
/// downloads, stats and settings.
class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(currentAccountProvider).value;
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabYou),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: debugMenuLabel,
              onPressed: () => context.push(DebugRoutes.hub),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          _SectionHeader(label: l10n.youServers),
          if (account != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.dns_outlined),
              ),
              title: Text(account.displayName),
              subtitle: Text(
                account.needsReauth
                    ? l10n.sessionExpiredBanner
                    : l10n.accountsUserOnServer(account.username, account.baseUrl.host),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.accounts),
            ),
          if (account == null && accounts.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.accountsTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.accounts),
            ),
          if (accounts.isEmpty)
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l10n.onboardingConnectServer),
              onTap: () => context.push(AppRoutes.addServer),
            ),
          _SectionHeader(label: l10n.youOnThisDevice),
          if (accounts.isNotEmpty) const DownloadsEntryTile(),
          ListTile(
            leading: const Icon(Icons.library_add_outlined),
            title: Text(l10n.youImportFiles),
            subtitle: Text(l10n.youImportFilesBody),
            onTap: () => context.push(AppRoutes.importFiles),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
