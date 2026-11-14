// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_client.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/storage/secure_store.dart';

import 'fake_http.dart';

class _NoEvents implements TokenEvents {
  @override
  void needsReauth(String accountId) {}

  @override
  void tokensRotated(String accountId) {}
}

/// A signed-in client for `a1` on a fake server answering from [handler].
/// The token is valid for a day, so no refresh happens.
Future<(AbsClient, FakeHttpAdapter)> testAbsClient(
  Future<FakeResponse> Function(RequestOptions request) handler, {
  String accountId = 'a1',
}) async {
  final store = MemorySecureStore();
  await store.writeTokens(
    accountId,
    access: fakeJwt(exp: DateTime.now().add(const Duration(days: 1))),
    refresh: 'refresh',
  );
  final (dio, adapter) = fakeDio(handler);
  // Refreshes go through a client of their own, as in the app.
  final (authDio, _) = fakeDio(handler);
  final refresher = TokenRefresher(
    store: store,
    events: _NoEvents(),
    apiFor: (_) async => AbsAuthApi(Uri.parse('https://books.example.com'), dio: authDio),
  );
  final client = AbsClient.create(
    accountId: accountId,
    baseUrl: Uri.parse('https://books.example.com'),
    store: store,
    refresher: refresher,
    dio: dio,
  );
  return (client, adapter);
}
