// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Runs against the local dev server (tool/abs-dev). Skipped automatically
// when it is not running or its passwords file is missing, so CI and a fresh
// clone pass without it.
@Tags(['server'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_client.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/net/server_probe.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

final devServer = Uri.parse('http://localhost:13378');

String? devPassword(String user) {
  final file = File('tool/abs-dev/.env.local');
  if (!file.existsSync()) return null;
  final key = user == 'root' ? 'ABS_ROOT_PASSWORD' : 'ABS_AFFLUENT_PASSWORD';
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('$key=')) return line.substring(key.length + 1).trim();
  }
  return null;
}

Future<String?> skipReason() async {
  if (devPassword('affluent') == null) return 'tool/abs-dev/.env.local not found (run tool/abs-dev/setup.dart)';
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(devServer.replace(path: '/ping'));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200 ? null : 'dev server answered ${response.statusCode}';
  } on Object {
    return 'dev server not running on $devServer';
  }
}

class NoEvents implements TokenEvents {
  @override
  void needsReauth(String accountId) {}

  @override
  void tokensRotated(String accountId) {}
}

Future<void> main() async {
  final skip = await skipReason();

  // The real network, not the test binding's mocked HTTP.
  setUpAll(() => HttpOverrides.global = null);

  test('probe, sign in, call the API, refresh with rotation, sign out', () async {
    final probe = await ServerProbe(dio: Dio()).probe('localhost:13378');
    expect(probe, isA<ProbeOk>(), reason: '$probe');
    final server = probe as ProbeOk;
    expect(server.baseUrl, devServer, reason: 'https fails locally, http answers');
    expect(server.authMethods, contains(AuthMethod.local));

    final auth = AbsAuthApi(server.baseUrl);
    final login = await auth.login('affluent', devPassword('affluent')!);
    expect(login.username, 'affluent');
    expect(login.user.containsKey('token'), isFalse, reason: 'legacy token is dropped');

    final store = MemorySecureStore();
    await store.writeTokens('live', access: login.accessToken, refresh: login.refreshToken);
    final refresher = TokenRefresher(store: store, events: NoEvents(), apiFor: (_) async => auth);
    final client = AbsClient.create(accountId: 'live', baseUrl: server.baseUrl, store: store, refresher: refresher);
    final me = await client.authorize();
    expect((me['user'] as Map)['username'], 'affluent');

    expect(await refresher.refresh('live'), isTrue);
    final rotated = await store.readRefresh('live');
    expect(rotated, isNot(login.refreshToken), reason: 'refresh rotates');
    expect(await client.authorize(), isA<Map<String, Object?>>(), reason: 'new access token works');

    await auth.logout(rotated!);
    await expectLater(auth.refresh(rotated), throwsA(isA<AbsUnauthorized>()), reason: 'logout revokes');
    client.close();
  }, skip: skip);

  test('wrong password is AbsUnauthorized', () async {
    await expectLater(AbsAuthApi(devServer).login('affluent', 'wrong-password'), throwsA(isA<AbsUnauthorized>()));
  }, skip: skip);
}
