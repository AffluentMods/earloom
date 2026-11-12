# Phase 1: Accounts, auth and realtime

Goal: a user can add one or more ABS servers, sign in with username/password or OIDC, stay signed in through token rotation, switch accounts, and receive live updates over the socket. Losing auth never breaks offline listening.

Branch: `phase-1-auth`

---

## 1.1 Data model

`lib/core/db/tables/accounts.dart` (GlobalDb)

| Column | Type | Notes |
|---|---|---|
| `id` | text PK | uuid v4, local only |
| `serverUrl` | text | normalized, no trailing slash |
| `serverName` | text nullable | from server settings if present |
| `serverVersion` | text | from `/status` |
| `userId` | text | ABS user id |
| `username` | text | |
| `userType` | text | root, admin, user, guest |
| `authMethod` | text | `local` or `openid` |
| `status` | text | `active`, `needsReauth` |
| `isCurrent` | bool | exactly one row true |
| `createdAt`, `lastUsedAt` | int | epoch ms |

Secrets (`lib/core/storage/secure_store.dart`), never in SQLite:
- `acct.<id>.access`
- `acct.<id>.refresh`
- `acct.<id>.headers` (JSON map of custom headers, for reverse proxies like Cloudflare Access)

Per-account cache DB: `account_<id>.sqlite` (`AccountDb`). Deleting an account deletes this file and its downloads folder (after asking, see 1.8).

### Acceptance
- [ ] Unit test: only one account can be `isCurrent`
- [ ] Tokens are only ever read and written through `SecureStore`
- [ ] Removing an account removes its secrets

---

## 1.2 Add server flow

Files: `lib/features/accounts/ui/add_server_screen.dart`, `lib/core/net/server_probe.dart`

Steps the user sees:
1. **Server address.** One field. Accept `host`, `host:port`, full URL. Advanced expander: custom headers (key/value list).
2. **Probe.** Normalize: if no scheme, try `https://` first, then `http://`. Call `/ping` then `/status`.
3. **Result card.** Server version, available sign-in methods. Errors are specific: unreachable, not an ABS server, server not initialized, version too old.
4. **Sign in** (1.3 or 1.4).

```dart
// lib/core/net/server_probe.dart
sealed class ProbeResult {}
class ProbeOk extends ProbeResult {
  ProbeOk({required this.baseUrl, required this.version, required this.authMethods, required this.isCleartext, this.oidcButtonText});
  final Uri baseUrl;
  final Version version;
  final Set<AuthMethod> authMethods;
  final bool isCleartext;
  final String? oidcButtonText;
}
class ProbeUnreachable extends ProbeResult { ProbeUnreachable(this.cause); final Object cause; }
class ProbeNotAbs extends ProbeResult {}
class ProbeNotInitialized extends ProbeResult {}
class ProbeTooOld extends ProbeResult { ProbeTooOld(this.version); final Version version; }

const minServerVersion = Version(2, 26, 0);
const securityAdvisoryBelow = Version(2, 36, 0); // CVE-2026-73085

class ServerProbe {
  Future<ProbeResult> probe(String input, {Map<String, String> headers = const {}}) async { /* ... */ }
}
```

Rules:
- `http://` is allowed (homelab users) but shows an inline warning card. Do not block.
- Servers below 2.26.0 are blocked with a clear message to update the server.
- After login, if the user is admin or root and the server is below 2.36.0, show a dismissible security banner on the You tab linking to the ABS release notes.

### Platform config
- iOS `Info.plist`: `NSLocalNetworkUsageDescription` (l10n via `InfoPlist.strings`), `NSAppTransportSecurity` with `NSAllowsLocalNetworking` true and `NSAllowsArbitraryLoads` true. Keep an App Review note ready: "Users connect to their own self-hosted servers, often on LAN without TLS."
- Android `res/xml/network_security_config.xml`: cleartext permitted, trust system CAs and user-installed CAs (homelab users with their own CA). Document the tradeoff in a code comment.

### Acceptance
- [ ] `localhost:13378`, `http://10.x.x.x:13378`, `https://abs.example.com` and a URL with a subpath all probe correctly
- [ ] Each failure type shows its own message (widget tests with fake probe)
- [ ] Cleartext warning appears for http
- [ ] Custom headers are sent on probe and every later request

---

## 1.3 Local login

`POST /login` with `x-return-tokens: true`. Store access + refresh in `SecureStore`, user info in `accounts`, then call `/api/authorize` to warm the cache.

UI: username, password (show/hide), sign in button with loading state. Rate-limit errors from the server (ABS has an auth rate limiter) show "Too many attempts, wait a minute".

### Acceptance
- [ ] Wrong password, rate limit, and network errors each have distinct messages
- [ ] Password is never persisted
- [ ] Login works against dev server for `root` and `affluent`

---

## 1.4 OIDC (SSO) login

Files: `lib/features/accounts/data/oidc_login.dart`

- Only shown when `/status` lists `openid`. Button label from server config if provided.
- PKCE S256 with a fresh verifier per attempt, random `state`.
- Redirect URI: `earloom://oauth`. Never `audiobookshelf://oauth` (ABS third-party rules).
- Use `flutter_web_auth_2` (ASWebAuthenticationSession on iOS, Custom Tabs on Android).
- Exact params and callback exchange come from `docs/abs-api.md` (Phase 0 answers).

Admin help sheet (shown on OIDC failure with a redirect error, and from a "Having trouble?" link):
> Your server admin needs to add `earloom://oauth` to Allowed Mobile Redirect URIs in Audiobookshelf settings, under Authentication.

### Acceptance
- [ ] OIDC login works against a test IdP (Authentik or Keycloak in `tool/abs-dev`, optional compose profile `oidc`)
- [ ] State mismatch is rejected
- [ ] Cancelled browser returns to the sign-in screen without an error toast

---

## 1.5 Token refresh

Files: `lib/core/net/auth_interceptor.dart`, `lib/core/net/token_refresher.dart`, `lib/core/net/abs_client.dart`

Rules:
- Refresh tokens rotate. Exactly one refresh in flight per account (single-flight).
- Persist the new refresh token before using the new access token.
- A network failure during refresh is NOT a logout. Only a 401 or 403 from `/auth/refresh` marks the account `needsReauth`.
- If a request failed with an access token that has since been replaced, retry with the new one without refreshing again.
- Proactive refresh: decode the JWT `exp` (no signature check needed) and refresh when under 2 minutes remain, on app resume, before starting playback, and before starting downloads.

```dart
// lib/core/net/token_refresher.dart
class TokenRefresher {
  TokenRefresher(this._store, this._bareDioFor, this._events);
  final SecureStore _store;
  final Dio Function(String accountId) _bareDioFor; // no auth interceptor
  final AccountEvents _events;
  final _inflight = <String, Future<bool>>{};

  Future<bool> refresh(String accountId) =>
      _inflight[accountId] ??= _doRefresh(accountId).whenComplete(() => _inflight.remove(accountId));

  Future<bool> _doRefresh(String accountId) async {
    final refreshToken = await _store.readRefresh(accountId);
    if (refreshToken == null) return false;
    try {
      final res = await _bareDioFor(accountId).post(
        '/auth/refresh',
        options: Options(headers: {'x-refresh-token': refreshToken}),
      );
      final user = res.data['user'] as Map<String, dynamic>;
      await _store.writeTokens(
        accountId,
        access: user['accessToken'] as String,
        refresh: (user['refreshToken'] as String?) ?? refreshToken,
      );
      _events.tokensRotated(accountId); // socket re-auths on this
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        _events.needsReauth(accountId);
        return false;
      }
      rethrow; // offline or server down: caller fails, account stays active
    }
  }
}
```

```dart
// lib/core/net/auth_interceptor.dart
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this.accountId, this._store, this._refresher, this._retryDio);
  final String accountId;
  final SecureStore _store;
  final TokenRefresher _refresher;
  final Dio _retryDio;

  @override
  Future<void> onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final access = await _store.readAccess(accountId);
    if (access != null) {
      o.headers['Authorization'] = 'Bearer $access';
      o.extra['sentAccess'] = access;
    }
    o.headers.addAll(await _store.readCustomHeaders(accountId));
    h.next(o);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler h) async {
    final req = err.requestOptions;
    if (err.response?.statusCode != 401 || req.extra['retried'] == true) return h.next(err);

    final current = await _store.readAccess(accountId);
    if (current == null || current == req.extra['sentAccess']) {
      try {
        if (!await _refresher.refresh(accountId)) return h.next(err);
      } catch (_) {
        return h.next(err);
      }
    }
    req.headers['Authorization'] = 'Bearer ${await _store.readAccess(accountId)}';
    req.extra['retried'] = true;
    try {
      h.resolve(await _retryDio.fetch(req));
    } on DioException catch (e) {
      h.next(e);
    }
  }
}
```

`lib/core/net/redacting_logger.dart`: debug-only dio logger that replaces `Authorization`, `x-refresh-token`, `cookie`, `set-cookie` values and any `password` JSON field with `<redacted>`.

### Tests (`test/core/net/`)
- 10 concurrent requests all get 401: exactly one `/auth/refresh` call, all 10 succeed after.
- Refresh returns 401: account goes `needsReauth`, no retry loop.
- Refresh throws a socket error: account stays `active`.
- Run the integration suite against the short-token compose override for 15 minutes of simulated use: zero forced logouts.

### Acceptance
- [ ] All tests above pass
- [ ] No token value appears in debug logs (grep test on captured log output)

---

## 1.6 Session expired UX

When an account becomes `needsReauth`:
- Downloaded books keep playing. Progress keeps writing to the outbox (Phase 4).
- A non-blocking banner on Home: "Sign in again to sync". Tapping opens the right sign-in method prefilled with the username.
- After sign-in, the outbox flushes automatically.
- Never delete downloads or local progress because of an auth failure.

### Acceptance
- [ ] Revoke the session on the server mid-use: app keeps playing a downloaded book, shows the banner, re-auth flushes queued progress

---

## 1.7 Multiple accounts

- You tab > Accounts: list with server name, username, status dot (dot = connection status only).
- Switch account: sync and close the current playback session, disconnect socket, swap `AccountDb`, reconnect, go to Home.
- Different users on the same server are separate accounts.

### Acceptance
- [ ] Two accounts on two servers, switch back and forth: no data from account A ever renders under account B
- [ ] Switching mid-playback saves progress to the right account

---

## 1.8 Sign out and remove

- Sign out: `POST /logout` with `x-refresh-token`, clear tokens, keep cache and downloads, account row goes `needsReauth`.
- Remove account: sign out, then ask "Also delete X GB of downloads?" Default: delete.

---

## 1.9 Realtime socket

File: `lib/core/socket/abs_socket.dart`

- Connect after login and on app foreground. Disconnect after 60s in background unless playing.
- Authenticate with the access token as verified in Phase 0. Re-authenticate on `tokensRotated`.
- Events in Phase 1: just log and expose a `Stream<AbsSocketEvent>`. Phase 2 and 3 consume progress and item events.
- Exponential backoff with jitter on reconnect, capped at 60s.

```dart
sealed class AbsSocketEvent {}
class ProgressUpdated extends AbsSocketEvent { ProgressUpdated(this.itemId, this.episodeId, this.progress); /* ... */ }
class ItemUpdated extends AbsSocketEvent { ItemUpdated(this.itemId); final String itemId; }
class ItemAdded extends AbsSocketEvent { ItemAdded(this.itemId); final String itemId; }
class ItemRemoved extends AbsSocketEvent { ItemRemoved(this.itemId); final String itemId; }
```

### Acceptance
- [ ] Change progress in the ABS web UI: event arrives in the app within 2s
- [ ] Socket survives a token rotation without a reconnect storm

---

## l10n keys added in Phase 1

```
addServerTitle, addServerAddressLabel, addServerAddressHint, addServerContinue,
addServerAdvanced, addServerCustomHeaders, addServerHeaderName, addServerHeaderValue,
probeChecking, probeUnreachable, probeNotAbs, probeNotInitialized, probeTooOld(version),
probeCleartextWarning, probeServerVersion(version),
signInTitle, signInUsername, signInPassword, signInShowPassword, signInButton,
signInWrongCredentials, signInRateLimited, signInWithSso(provider), signInSsoTrouble,
ssoAdminHelpTitle, ssoAdminHelpBody(redirectUri),
sessionExpiredBanner, sessionExpiredAction,
securityAdvisoryBanner(version), securityAdvisoryLearnMore,
accountsTitle, accountsAdd, accountsSwitch, accountsSignOut, accountsRemove,
accountsRemoveDownloadsPrompt(size), accountsRemoveDownloadsKeep, accountsRemoveDownloadsDelete
```

## Phase 1 done when
- [ ] All section checklists ticked
- [ ] Router sends a fresh install to onboarding and an existing install to Home
- [ ] `tool/check.sh` passes
