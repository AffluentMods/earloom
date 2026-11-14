// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/db/global_db.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/account_session.dart';
import '../../downloads/data/offline_providers.dart' show removeAccountOfflineData;
import '../data/accounts_repository.dart';
import '../../../core/util/dev_log.dart';

/// Every server account on this phone: which one is in use, switching,
/// signing out and removing.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        children: [
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(l10n.accountsEmpty, style: Theme.of(context).textTheme.bodyLarge),
            ),
          for (final account in accounts) _AccountTile(account: account),
          const SizedBox(height: Space.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/accounts/add'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.accountsAdd),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});

  final AccountRow account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final host = account.baseUrl.host;
    final status = account.needsReauth ? l10n.accountsSignedOut : (account.isCurrent ? l10n.accountsCurrent : null);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.xs, Space.xs),
      leading: CircleAvatar(
        backgroundColor: account.isCurrent ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        foregroundColor: account.isCurrent ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        child: Text(account.username.isEmpty ? '?' : account.username.characters.first.toUpperCase()),
      ),
      title: Text(account.displayName, style: text.titleMedium),
      subtitle: Text(
        [l10n.accountsUserOnServer(account.username, host), ?status].join('  ·  '),
        style: text.bodySmall?.copyWith(color: account.needsReauth ? scheme.error : scheme.onSurfaceVariant),
      ),
      selected: account.isCurrent,
      onTap: account.isCurrent
          ? null
          : () async {
              await HapticFeedback.selectionClick();
              await ref.read(accountsRepositoryProvider).switchTo(account.id);
              if (context.mounted) context.go('/home');
            },
      trailing: PopupMenuButton<_Action>(
        tooltip: l10n.accountsMenu,
        onSelected: (action) => _run(context, ref, action),
        itemBuilder: (context) => [
          if (!account.isCurrent) PopupMenuItem(value: _Action.use, child: Text(l10n.accountsUseThis)),
          if (account.needsReauth)
            PopupMenuItem(value: _Action.signIn, child: Text(l10n.accountsSignIn))
          else
            PopupMenuItem(value: _Action.signOut, child: Text(l10n.accountsSignOut)),
          PopupMenuItem(value: _Action.remove, child: Text(l10n.accountsRemove)),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, _Action action) async {
    final repository = ref.read(accountsRepositoryProvider);
    switch (action) {
      case _Action.use:
        await repository.switchTo(account.id);
        if (context.mounted) context.go('/home');
      case _Action.signIn:
        if (context.mounted) unawaited(context.push('/accounts/${account.id}/signin'));
      case _Action.signOut:
        await repository.signOut(account.id);
      case _Action.remove:
        final confirmed = await _confirmRemove(context);
        if (confirmed != true) return;
        await repository.remove(account.id);
        try {
          await removeAccountOfflineData(ref, account.id);
        } on Object catch (e) {
          // Best effort: what is left can no longer sync and is harmless.
          devLog('Offline data of a removed account not cleared: $e');
        }
        await _deleteLocalData(account.id);
    }
  }

  Future<bool?> _confirmRemove(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountsRemoveTitle(account.displayName)),
        content: Text(l10n.accountsRemoveBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.genericCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.accountsRemoveConfirm),
          ),
        ],
      ),
    );
  }

  /// Deletes the account's cache database and downloads folder. The
  /// session (and its open database) is already gone once the account is
  /// no longer current.
  static Future<void> _deleteLocalData(String accountId) async {
    try {
      final support = await getApplicationSupportDirectory();
      for (final name in [
        'account_$accountId.sqlite',
        'account_$accountId.sqlite-wal',
        'account_$accountId.sqlite-shm',
      ]) {
        final file = File('${support.path}/$name');
        if (file.existsSync()) await file.delete();
      }
      final downloads = Directory('${support.path}/accounts/$accountId');
      if (downloads.existsSync()) await downloads.delete(recursive: true);
    } on FileSystemException {
      // Best effort: leftover cache files are harmless and small.
    }
  }
}

enum _Action { use, signIn, signOut, remove }

/// "Sign in again to sync" for the current account, shown on Home.
class ReauthBanner extends ConsumerWidget {
  const ReauthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider).value;
    if (account == null || !account.needsReauth) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return InlineNotice(
      icon: Icons.sync_problem_rounded,
      tone: NoticeTone.warning,
      message: l10n.sessionExpiredBanner,
      action: TextButton(
        onPressed: () => context.push('/accounts/${account.id}/signin'),
        child: Text(l10n.sessionExpiredAction),
      ),
    );
  }
}
