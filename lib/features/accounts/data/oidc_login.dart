// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../../core/net/abs_auth_api.dart';
import '../../../core/net/abs_errors.dart';

/// The app's own redirect for single sign-on. Admins add exactly this to
/// "Allowed Mobile Redirect URIs" (never audiobookshelf://oauth, which
/// belongs to the official app).
const oidcRedirectUri = 'earloom://oauth';

/// Runs the mobile single sign-on flow of docs/abs-api.md section 5 in the
/// system browser (ASWebAuthenticationSession on iOS, Custom Tabs on
/// Android). Returns null when the user closes the browser.
class OidcLogin {
  OidcLogin({Future<String> Function(Uri url)? openBrowser}) : _openBrowser = openBrowser ?? _systemBrowser;

  final Future<String> Function(Uri url) _openBrowser;

  static Future<String> _systemBrowser(Uri url) =>
      FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: 'earloom');

  Future<AuthResult?> signIn(AbsAuthApi api) async {
    final pkce = OidcPkce.generate();
    final start = await api.startOidc(pkce: pkce, redirectUri: oidcRedirectUri);
    final String callback;
    try {
      callback = await _openBrowser(start.authorizationUrl);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED' || e.code == 'CANCELLED') return null;
      throw AbsUnexpected('Browser sign-in failed: ${e.code} ${e.message ?? ''}');
    }
    final uri = Uri.parse(callback);
    if (uri.queryParameters['state'] != pkce.state) {
      throw const OidcStateMismatch('state in the callback did not match');
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw AbsUnexpected('Callback without a code: ${uri.queryParameters['error'] ?? 'no error given'}');
    }
    return api.finishOidc(start: start, pkce: pkce, code: code);
  }
}
