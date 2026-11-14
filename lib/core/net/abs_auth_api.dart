// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'abs_errors.dart';

/// The user and tokens returned by a successful sign-in or refresh.
final class AuthResult {
  const AuthResult({
    required this.userId,
    required this.username,
    required this.userType,
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.defaultLibraryId,
    this.serverTimeZone,
  });

  final String userId;
  final String username;

  /// root, admin, user or guest.
  final String userType;
  final String accessToken;
  final String refreshToken;

  /// The whole user object (permissions, mediaProgress, bookmarks). The
  /// legacy `token` field is removed before this is kept anywhere.
  final Map<String, Object?> user;
  final String? defaultLibraryId;
  final String? serverTimeZone;

  bool get isAdmin => userType == 'root' || userType == 'admin';

  static AuthResult parse(Object? data) {
    if (data is! Map) throw const AbsUnexpected('Sign-in answer was not JSON');
    final user = data['user'];
    if (user is! Map) throw const AbsUnexpected('Sign-in answer has no user');
    final access = user['accessToken'];
    final refresh = user['refreshToken'];
    if (access is! String || refresh is! String || access.isEmpty || refresh.isEmpty) {
      throw const AbsUnexpected('Sign-in answer has no tokens. Is the server older than 2.26.0?');
    }
    final settings = data['serverSettings'];
    final copy = Map<String, Object?>.from(user)
      ..remove('token')
      ..remove('accessToken')
      ..remove('refreshToken');
    return AuthResult(
      userId: user['id'] as String,
      username: user['username'] as String,
      userType: (user['type'] as String?) ?? 'user',
      accessToken: access,
      refreshToken: refresh,
      user: copy,
      defaultLibraryId: data['userDefaultLibraryId'] as String?,
      serverTimeZone: settings is Map ? settings['timeZone'] as String? : null,
    );
  }
}

/// Sign-in, refresh and sign-out against one server. Uses a client without
/// the auth interceptor, so refreshing can never loop.
class AbsAuthApi {
  AbsAuthApi(this.baseUrl, {Dio? dio, this.headers = const {}}) : _dio = dio ?? Dio();

  final Uri baseUrl;
  final Map<String, String> headers;
  final Dio _dio;

  Uri _url(String path, [Map<String, String>? query]) =>
      baseUrl.replace(path: '${baseUrl.path}$path', queryParameters: query);

  Options _options([Map<String, String> extra = const {}]) => Options(
    headers: {...headers, ...extra},
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  );

  Future<AuthResult> login(String username, String password) async {
    try {
      final res = await _dio.postUri<Object?>(
        _url('/login'),
        data: {'username': username, 'password': password},
        options: _options({'x-return-tokens': 'true'}),
      );
      return AuthResult.parse(res.data);
    } on DioException catch (e) {
      throw AbsFailure.from(e);
    }
  }

  /// Rotates the refresh token. Throws [AbsUnauthorized] when the server no
  /// longer accepts it (sign in again), [AbsRateLimited] or
  /// [AbsUnreachable] when it should simply be tried later.
  Future<AuthResult> refresh(String refreshToken) async {
    try {
      final res = await _dio.postUri<Object?>(
        _url('/auth/refresh'),
        options: _options({'x-refresh-token': refreshToken}),
      );
      return AuthResult.parse(res.data);
    } on DioException catch (e) {
      throw AbsFailure.from(e);
    }
  }

  /// Ends the server session. Best effort: the server always answers 200,
  /// and being offline must not keep the user from signing out locally.
  Future<void> logout(String refreshToken) async {
    try {
      await _dio.postUri<Object?>(_url('/logout'), options: _options({'x-refresh-token': refreshToken}));
    } on DioException {
      // Ignored on purpose, see above.
    }
  }

  // --- OIDC (docs/abs-api.md section 5) ---

  /// Step 1: asks the server for the identity provider's sign-in page.
  /// Returns that URL and the cookies step 4 must send back.
  Future<OidcStart> startOidc({required OidcPkce pkce, required String redirectUri}) async {
    try {
      final res = await _dio.getUri<Object?>(
        _url('/auth/openid', {
          'response_type': 'code',
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'redirect_uri': redirectUri,
          'state': pkce.state,
          'client_id': 'Earloom',
        }),
        options: _options().copyWith(followRedirects: false, validateStatus: (s) => s != null && s < 500),
      );
      final location = res.headers.value('location');
      if (res.statusCode != 302 || location == null) {
        throw AbsHttpError(res.statusCode ?? 0, 'OIDC start answered HTTP ${res.statusCode}: ${res.data}');
      }
      return OidcStart(authorizationUrl: Uri.parse(location), cookies: _cookies(res));
    } on DioException catch (e) {
      throw AbsFailure.from(e);
    }
  }

  /// Step 4: trades the code for tokens, with the cookies from step 1.
  Future<AuthResult> finishOidc({required OidcStart start, required OidcPkce pkce, required String code}) async {
    try {
      final res = await _dio.getUri<Object?>(
        _url('/auth/openid/callback', {'state': pkce.state, 'code': code, 'code_verifier': pkce.verifier}),
        options: _options({'cookie': start.cookies}).copyWith(followRedirects: false),
      );
      return AuthResult.parse(res.data);
    } on DioException catch (e) {
      throw AbsFailure.from(e);
    }
  }

  static String _cookies(Response<Object?> res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    return raw.map((c) => c.split(';').first.trim()).where((c) => c.contains('=')).join('; ');
  }
}

final class OidcStart {
  const OidcStart({required this.authorizationUrl, required this.cookies});
  final Uri authorizationUrl;
  final String cookies;
}

/// A fresh PKCE verifier, its S256 challenge and a random state, per attempt.
final class OidcPkce {
  OidcPkce._(this.verifier, this.challenge, this.state);

  factory OidcPkce.generate([Random? random]) {
    final rng = random ?? Random.secure();
    String token(int bytes) => base64UrlEncode(List<int>.generate(bytes, (_) => rng.nextInt(256))).replaceAll('=', '');
    final verifier = token(48);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    return OidcPkce._(verifier, challenge, token(24));
  }

  final String verifier;
  final String challenge;
  final String state;
}
