// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The only place tokens and custom headers are read or written. Backed by
/// the iOS Keychain and Android's encrypted storage. Never SQLite, never logs.
abstract interface class SecureStore {
  Future<String?> readAccess(String accountId);
  Future<String?> readRefresh(String accountId);

  /// Writes both tokens. The refresh token is written first: if the app dies
  /// between the two writes, the next refresh still works.
  Future<void> writeTokens(String accountId, {required String access, required String refresh});

  Future<Map<String, String>> readCustomHeaders(String accountId);
  Future<void> writeCustomHeaders(String accountId, Map<String, String> headers);

  /// Removes every secret of the account.
  Future<void> deleteAccount(String accountId);

  /// Removes only the tokens (sign out keeps custom headers, so signing in
  /// again works behind the same reverse proxy).
  Future<void> deleteTokens(String accountId);
}

String _accessKey(String id) => 'acct.$id.access';
String _refreshKey(String id) => 'acct.$id.refresh';
String _headersKey(String id) => 'acct.$id.headers';

class PlatformSecureStore implements SecureStore {
  PlatformSecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Readable after the first unlock, so playback that starts from
            // the lock screen or the car can still refresh a token.
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccess(String accountId) => _storage.read(key: _accessKey(accountId));

  @override
  Future<String?> readRefresh(String accountId) => _storage.read(key: _refreshKey(accountId));

  @override
  Future<void> writeTokens(String accountId, {required String access, required String refresh}) async {
    await _storage.write(key: _refreshKey(accountId), value: refresh);
    await _storage.write(key: _accessKey(accountId), value: access);
  }

  @override
  Future<Map<String, String>> readCustomHeaders(String accountId) async {
    final raw = await _storage.read(key: _headersKey(accountId));
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {for (final e in decoded.entries) e.key.toString(): e.value.toString()};
  }

  @override
  Future<void> writeCustomHeaders(String accountId, Map<String, String> headers) {
    if (headers.isEmpty) return _storage.delete(key: _headersKey(accountId));
    return _storage.write(key: _headersKey(accountId), value: jsonEncode(headers));
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await deleteTokens(accountId);
    await _storage.delete(key: _headersKey(accountId));
  }

  @override
  Future<void> deleteTokens(String accountId) async {
    await _storage.delete(key: _accessKey(accountId));
    await _storage.delete(key: _refreshKey(accountId));
  }
}

/// In-memory store for tests and previews.
class MemorySecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> readAccess(String accountId) async => values[_accessKey(accountId)];

  @override
  Future<String?> readRefresh(String accountId) async => values[_refreshKey(accountId)];

  @override
  Future<void> writeTokens(String accountId, {required String access, required String refresh}) async {
    values[_refreshKey(accountId)] = refresh;
    values[_accessKey(accountId)] = access;
  }

  @override
  Future<Map<String, String>> readCustomHeaders(String accountId) async {
    final raw = values[_headersKey(accountId)];
    if (raw == null) return const {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> writeCustomHeaders(String accountId, Map<String, String> headers) async {
    if (headers.isEmpty) {
      values.remove(_headersKey(accountId));
    } else {
      values[_headersKey(accountId)] = jsonEncode(headers);
    }
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await deleteTokens(accountId);
    values.remove(_headersKey(accountId));
  }

  @override
  Future<void> deleteTokens(String accountId) async {
    values.remove(_accessKey(accountId));
    values.remove(_refreshKey(accountId));
  }
}
