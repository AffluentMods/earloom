// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/net/server_probe.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/account_session.dart';
import '../data/oidc_login.dart';

enum AddServerStage { address, checking, signIn, signingIn, done }

/// A custom header row being edited.
final class HeaderEntry {
  const HeaderEntry(this.name, this.value);
  final String name;
  final String value;
}

final class AddServerState {
  const AddServerState({
    this.stage = AddServerStage.address,
    this.server,
    this.probeFailure,
    this.signInFailure,
    this.headers = const [],
    this.reauthAccount,
  });

  final AddServerStage stage;
  final ProbeOk? server;

  /// Why the address did not lead to a usable server.
  final ProbeResult? probeFailure;
  final AbsFailure? signInFailure;
  final List<HeaderEntry> headers;

  /// Set when signing in again to an existing account.
  final AccountRow? reauthAccount;

  bool get busy => stage == AddServerStage.checking || stage == AddServerStage.signingIn;

  AddServerState copyWith({
    AddServerStage? stage,
    ProbeOk? server,
    ProbeResult? probeFailure,
    AbsFailure? signInFailure,
    List<HeaderEntry>? headers,
    bool clearServer = false,
    bool clearErrors = false,
  }) => AddServerState(
    stage: stage ?? this.stage,
    server: clearServer ? null : server ?? this.server,
    probeFailure: clearErrors ? null : probeFailure ?? this.probeFailure,
    signInFailure: clearErrors ? null : signInFailure ?? this.signInFailure,
    headers: headers ?? this.headers,
    reauthAccount: reauthAccount,
  );

  Map<String, String> get headerMap => {
    for (final h in headers)
      if (h.name.trim().isNotEmpty) h.name.trim(): h.value.trim(),
  };
}

final serverProbeProvider = Provider<ServerProbe>((ref) => ServerProbe(dio: Dio()));
final oidcLoginProvider = Provider<OidcLogin>((ref) => OidcLogin());

/// Drives the add server and sign-in screen. Keyed by the account id when
/// signing in again (null for a new server).
final addServerControllerProvider = NotifierProvider.autoDispose.family<AddServerController, AddServerState, String?>(
  AddServerController.new,
);

class AddServerController extends Notifier<AddServerState> {
  AddServerController(this.reauthAccountId);

  final String? reauthAccountId;

  @override
  AddServerState build() => const AddServerState();

  /// For signing in again: loads the account and checks its server.
  Future<void> loadReauth() async {
    final id = reauthAccountId;
    if (id == null) return;
    final account = await ref.read(globalDbProvider).accountById(id);
    if (account == null) return;
    final headers = await ref.read(secureStoreProvider).readCustomHeaders(id);
    state = AddServerState(
      reauthAccount: account,
      headers: [for (final e in headers.entries) HeaderEntry(e.key, e.value)],
    );
    await check(account.serverUrl);
  }

  void setHeaders(List<HeaderEntry> headers) => state = state.copyWith(headers: headers);

  Future<void> check(String address) async {
    state = state.copyWith(stage: AddServerStage.checking, clearErrors: true, clearServer: true);
    final result = await ref.read(serverProbeProvider).probe(address, headers: state.headerMap);
    if (!ref.mounted) return;
    if (result is ProbeOk) {
      state = state.copyWith(stage: AddServerStage.signIn, server: result);
    } else {
      state = state.copyWith(stage: AddServerStage.address, probeFailure: result);
    }
  }

  void changeServer() => state = state.copyWith(stage: AddServerStage.address, clearServer: true, clearErrors: true);

  Future<void> signIn(String username, String password) async {
    final server = state.server;
    if (server == null) return;
    state = state.copyWith(stage: AddServerStage.signingIn, clearErrors: true);
    try {
      await ref
          .read(accountsRepositoryProvider)
          .signInWithPassword(server, username: username, password: password, headers: state.headerMap);
      await _finish();
    } on AbsFailure catch (e) {
      if (ref.mounted) state = state.copyWith(stage: AddServerStage.signIn, signInFailure: e);
    }
  }

  Future<void> _finish() async {
    if (!ref.mounted) return;
    await ref.read(onboardingProvider.notifier).complete();
    if (ref.mounted) state = state.copyWith(stage: AddServerStage.done);
  }

  Future<void> signInWithSso() async {
    final server = state.server;
    if (server == null) return;
    state = state.copyWith(stage: AddServerStage.signingIn, clearErrors: true);
    try {
      final api = ref.read(authApiFactoryProvider)(server.baseUrl, state.headerMap);
      final result = await ref.read(oidcLoginProvider).signIn(api);
      if (!ref.mounted) return;
      if (result == null) {
        // The user closed the browser: back to the form, no error.
        state = state.copyWith(stage: AddServerStage.signIn);
        return;
      }
      await ref.read(accountsRepositoryProvider).completeOidc(server, result, headers: state.headerMap);
      await _finish();
    } on AbsFailure catch (e) {
      if (ref.mounted) state = state.copyWith(stage: AddServerStage.signIn, signInFailure: e);
    }
  }
}

/// Plain words for a probe that did not find a usable server.
String probeFailureMessage(AppLocalizations l10n, ProbeResult result) => switch (result) {
  ProbeUnreachable() => l10n.probeUnreachable,
  ProbeNotAbs() => l10n.probeNotAbs,
  ProbeNotInitialized() => l10n.probeNotInitialized,
  ProbeTooOld(:final version) => l10n.probeTooOld(version.toString()),
  ProbeInvalidAddress() => l10n.probeInvalidAddress,
  ProbeOk() => '',
};

String? probeFailureDetails(ProbeResult result) => switch (result) {
  ProbeUnreachable(:final details) => details,
  ProbeNotAbs(:final details) => details,
  ProbeNotInitialized(:final baseUrl) => 'isInit false at $baseUrl',
  ProbeTooOld(:final version) => 'serverVersion $version',
  _ => null,
};

/// Plain words for a failed sign-in.
String signInFailureMessage(AppLocalizations l10n, AbsFailure failure) => switch (failure) {
  AbsUnauthorized() => l10n.signInWrongCredentials,
  AbsRateLimited(:final retryAfter) when retryAfter != null => l10n.signInRateLimited(
    (retryAfter.inSeconds / 60).ceil().clamp(1, 60),
  ),
  AbsRateLimited() => l10n.signInRateLimitedNoTime,
  AbsUnreachable() => l10n.signInUnreachable,
  OidcStateMismatch() => l10n.ssoStateMismatch,
  _ => l10n.signInFailed,
};
