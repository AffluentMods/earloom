// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'abs_auth_api.dart';
import 'abs_errors.dart';
import 'jwt.dart';
import '../storage/secure_store.dart';

/// What the app learns from refreshing.
abstract interface class TokenEvents {
  /// New tokens are stored (the socket re-authenticates on this).
  void tokensRotated(String accountId);

  /// The server no longer accepts the refresh token: sign in again.
  void needsReauth(String accountId);
}

/// Refreshes tokens with at most one refresh in flight per account.
///
/// Refresh tokens rotate and the server's auth rate limit is shared by every
/// client behind the same address (40 per 10 minutes), so two refreshers
/// racing would waste the budget and confuse the session. Rules from
/// docs/abs-api.md section 18:
/// - 401 from the server: sign in again ([TokenEvents.needsReauth]).
/// - 429 or no network: still signed in, try later (the error is rethrown).
class TokenRefresher {
  TokenRefresher({
    required this._store,
    required this._apiFor,
    required this._events,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SecureStore _store;
  final Future<AbsAuthApi> Function(String accountId) _apiFor;
  final TokenEvents _events;
  final DateTime Function() _clock;
  final _inflight = <String, Future<bool>>{};

  /// Refreshes now. Returns false when the account must sign in again.
  /// Throws [AbsRateLimited] or [AbsUnreachable] when it should be retried
  /// later. Concurrent callers share one refresh.
  Future<bool> refresh(String accountId) {
    // The cleanup must not return the removed future: whenComplete would
    // then wait on the refresh itself and never finish.
    return _inflight[accountId] ??= _doRefresh(accountId).whenComplete(() {
      _inflight.remove(accountId);
    });
  }

  /// Refreshes only when the access token expires within two minutes. Used
  /// on resume, before playback and before downloads.
  Future<bool> refreshIfNeeded(String accountId) async {
    final access = await _store.readAccess(accountId);
    if (access != null && !jwtExpiresSoon(access, now: _clock())) return true;
    return refresh(accountId);
  }

  Future<bool> _doRefresh(String accountId) async {
    final refreshToken = await _store.readRefresh(accountId);
    if (refreshToken == null) {
      _events.needsReauth(accountId);
      return false;
    }
    try {
      final result = await (await _apiFor(accountId)).refresh(refreshToken);
      await _store.writeTokens(accountId, access: result.accessToken, refresh: result.refreshToken);
      _events.tokensRotated(accountId);
      return true;
    } on AbsUnauthorized {
      _events.needsReauth(accountId);
      return false;
    }
  }
}
