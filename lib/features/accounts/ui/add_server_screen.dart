// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/net/server_probe.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/oidc_login.dart';
import 'add_server_controller.dart';

/// Connect a new server, or sign in again to an existing account
/// ([reauthAccountId]). Address first, then the sign-in methods the server
/// offers.
class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key, this.reauthAccountId});

  final String? reauthAccountId;

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  AddServerController get _controller => ref.read(addServerControllerProvider(widget.reauthAccountId).notifier);

  @override
  void initState() {
    super.initState();
    if (widget.reauthAccountId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _controller.loadReauth();
        final account = ref.read(addServerControllerProvider(widget.reauthAccountId)).reauthAccount;
        if (account != null && mounted) {
          _address.text = account.serverUrl;
          _username.text = account.username;
          _passwordFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _check() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_controller.check(_address.text));
  }

  void _signIn() {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_controller.signIn(_username.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(addServerControllerProvider(widget.reauthAccountId));
    ref.listen(addServerControllerProvider(widget.reauthAccountId).select((s) => s.stage), (_, stage) {
      if (stage == AddServerStage.done) {
        unawaited(HapticFeedback.mediumImpact());
        context.go('/home');
      }
    });
    final reauth = state.reauthAccount;
    final found = state.server;
    final signingIn = state.stage == AddServerStage.signingIn;

    return Scaffold(
      appBar: AppBar(title: Text(reauth == null ? l10n.addServerTitle : l10n.signInAgainTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xxl),
          children: [
            Text(
              reauth == null ? l10n.addServerIntro : l10n.signInAgainBody(Uri.parse(reauth.serverUrl).host),
              style: text.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.xl),
            if (found == null) ...[
              TextField(
                controller: _address,
                enabled: !state.busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.go,
                autofillHints: const [AutofillHints.url],
                onSubmitted: (_) => _check(),
                decoration: InputDecoration(
                  labelText: l10n.addServerAddressLabel,
                  hintText: l10n.addServerAddressHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: Space.sm),
              _HeadersEditor(
                headers: state.headers,
                enabled: !state.busy,
                onChanged: _controller.setHeaders,
              ),
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: state.busy ? null : _check,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: state.stage == AddServerStage.checking
                    ? _Busy(label: l10n.probeChecking)
                    : Text(l10n.genericContinue),
              ),
              if (state.probeFailure != null) ...[
                const SizedBox(height: Space.lg),
                ErrorNotice(
                  message: probeFailureMessage(l10n, state.probeFailure!),
                  details: probeFailureDetails(state.probeFailure!),
                ),
              ],
            ] else ...[
              _ServerCard(
                server: found,
                onChange: reauth == null && !state.busy ? _controller.changeServer : null,
              ),
              if (found.isCleartext) ...[
                const SizedBox(height: Space.md),
                InlineNotice(
                  icon: Icons.lock_open_rounded,
                  tone: NoticeTone.warning,
                  message: l10n.probeCleartextWarning,
                ),
              ],
              const SizedBox(height: Space.xl),
              if (found.authMethods.contains(AuthMethod.local)) ...[
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        controller: _username,
                        enabled: !signingIn,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: l10n.signInUsername,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !signingIn,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: l10n.signInPassword,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? l10n.signInShowPassword : l10n.signInHidePassword,
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                ListenableBuilder(
                  listenable: Listenable.merge([_username, _password]),
                  builder: (context, _) => FilledButton(
                    onPressed: signingIn || _username.text.trim().isEmpty || _password.text.isEmpty ? null : _signIn,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: signingIn ? _Busy(label: l10n.signInButton) : Text(l10n.signInButton),
                  ),
                ),
              ],
              if (found.authMethods.contains(AuthMethod.openid)) ...[
                if (found.authMethods.contains(AuthMethod.local)) _OrDivider(label: l10n.signInOr),
                OutlinedButton.icon(
                  onPressed: signingIn ? null : () => unawaited(_controller.signInWithSso()),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: Text(l10n.signInWithSso(found.oidcButtonText ?? l10n.signInSsoDefault)),
                ),
                Align(
                  child: TextButton(
                    onPressed: () => _showSsoHelp(context),
                    child: Text(l10n.signInSsoTrouble),
                  ),
                ),
              ],
              if (state.signInFailure != null) ...[
                const SizedBox(height: Space.lg),
                ErrorNotice(
                  message: signInFailureMessage(l10n, state.signInFailure!),
                  details: state.signInFailure!.details,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showSsoHelp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.ssoAdminHelpTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              Text(l10n.ssoAdminHelpBody(oidcRedirectUri), style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: Space.lg),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: oidcRedirectUri));
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(l10n.genericCopyDetails),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ),
      const SizedBox(width: Space.md),
      Text(label),
    ],
  );
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server, this.onChange});

  final ProbeOk server;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final host = server.baseUrl.hasPort ? '${server.baseUrl.host}:${server.baseUrl.port}' : server.baseUrl.host;
    final address = '$host${server.baseUrl.path}';
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.sm, Space.lg),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Space.md)),
            child: Icon(Icons.check_rounded, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  l10n.probeServerVersion(server.version.toString()),
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onChange != null) TextButton(onPressed: onChange, child: Text(l10n.probeChangeServer)),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

/// Optional custom headers for servers behind an authenticating proxy.
class _HeadersEditor extends StatelessWidget {
  const _HeadersEditor({required this.headers, required this.enabled, required this.onChanged});

  final List<HeaderEntry> headers;
  final bool enabled;
  final ValueChanged<List<HeaderEntry>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: headers.isNotEmpty,
        title: Text(l10n.addServerAdvanced, style: Theme.of(context).textTheme.titleSmall),
        childrenPadding: const EdgeInsets.only(bottom: Space.sm),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.addServerCustomHeadersHelp,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final (i, h) in headers.indexed)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: h.name,
                      enabled: enabled,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.addServerHeaderName,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => onChanged([...headers]..[i] = HeaderEntry(v, h.value)),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: TextFormField(
                      initialValue: h.value,
                      enabled: enabled,
                      autocorrect: false,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.addServerHeaderValue,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => onChanged([...headers]..[i] = HeaderEntry(h.name, v)),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.addServerRemoveHeader,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: enabled ? () => onChanged([...headers]..removeAt(i)) : null,
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled ? () => onChanged([...headers, const HeaderEntry('', '')]) : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addServerAddHeader),
            ),
          ),
        ],
      ),
    );
  }
}
