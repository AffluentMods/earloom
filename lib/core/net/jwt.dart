// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

/// When a JWT expires, read from its payload. The signature is not checked:
/// this only decides when to refresh, the server still validates the token.
/// Returns null when the token has no readable expiry.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(), isUtc: true);
  } on FormatException {
    return null;
  }
}

/// True when [token] expires within [margin] of [now] (or has no expiry we
/// can read, in which case refreshing is the safe choice).
bool jwtExpiresSoon(String token, {required DateTime now, Duration margin = const Duration(minutes: 2)}) {
  final expiry = jwtExpiry(token);
  if (expiry == null) return true;
  return !expiry.isAfter(now.toUtc().add(margin));
}
