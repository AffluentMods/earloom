// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';

import '../storage/secure_store.dart';
import 'abs_errors.dart';
import 'token_refresher.dart';

/// Adds the access token and the account's custom headers to each request,
/// refreshes ahead of expiry, and retries once after a 401 with new tokens.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.accountId,
    required this._store,
    required this._refresher,
    required this._retryDio,
  });

  final String accountId;
  final SecureStore _store;
  final TokenRefresher _refresher;
  final Dio _retryDio;

  static const _sentKey = 'earloom.sentAccess';
  static const _retriedKey = 'earloom.retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      // Refresh ahead of expiry so long sessions never see a 401. Being
      // offline or rate limited here is fine: send with what we have.
      await _refresher.refreshIfNeeded(accountId);
    } on AbsFailure {
      // Ignored on purpose, see above.
    }
    final access = await _store.readAccess(accountId);
    options.headers.addAll(await _store.readCustomHeaders(accountId));
    if (access != null) {
      options.headers['Authorization'] = 'Bearer $access';
      options.extra[_sentKey] = access;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 || request.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    final current = await _store.readAccess(accountId);
    // Another request may already have refreshed while this one was in
    // flight: then just retry with the newer token.
    if (current == null || current == request.extra[_sentKey]) {
      try {
        if (!await _refresher.refresh(accountId)) return handler.next(err);
      } on AbsFailure {
        return handler.next(err);
      }
    }
    final fresh = await _store.readAccess(accountId);
    request.headers['Authorization'] = 'Bearer $fresh';
    request.extra[_sentKey] = fresh;
    request.extra[_retriedKey] = true;
    try {
      handler.resolve(await _retryDio.fetch<Object?>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
