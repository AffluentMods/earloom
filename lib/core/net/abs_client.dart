// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/secure_store.dart';
import 'abs_errors.dart';
import 'auth_interceptor.dart';
import 'redacting_logger.dart';
import 'token_refresher.dart';

/// Typed wrapper around the Audiobookshelf API for one account. Every call
/// the app makes to a server goes through an instance of this class.
///
/// Endpoints are added as features need them; shapes are documented in
/// docs/abs-api.md. Errors surface as [AbsFailure].
class AbsClient {
  AbsClient._(this.accountId, this.baseUrl, this.dio);

  factory AbsClient.create({
    required String accountId,
    required Uri baseUrl,
    required SecureStore store,
    required TokenRefresher refresher,
    Dio? dio,
  }) {
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
    client.interceptors.add(
      AuthInterceptor(accountId: accountId, store: store, refresher: refresher, retryDio: client),
    );
    if (kDebugMode) client.interceptors.add(RedactingLogger());
    return AbsClient._(accountId, baseUrl, client);
  }

  final String accountId;
  final Uri baseUrl;
  final Dio dio;

  /// An absolute URL on this server for [path] (which starts with a slash).
  Uri url(String path, [Map<String, Object?>? query]) => baseUrl.replace(
    path: '${baseUrl.path}$path',
    queryParameters: query?.map((k, v) => MapEntry(k, v?.toString())),
  );

  /// [cancelToken] drops a request whose answer is no longer wanted (a
  /// stale search); it then fails with [AbsCancelled].
  Future<T> get<T>(String path, {Map<String, Object?>? query, CancelToken? cancelToken}) =>
      _wrap(() => dio.getUri<T>(url(path, query), cancelToken: cancelToken));

  Future<T> post<T>(String path, {Object? body, Map<String, Object?>? query}) =>
      _wrap(() => dio.postUri<T>(url(path, query), data: body));

  Future<T> patch<T>(String path, {Object? body}) => _wrap(() => dio.patchUri<T>(url(path), data: body));

  Future<T> delete<T>(String path) => _wrap(() => dio.deleteUri<T>(url(path)));

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data as T;
    } on DioException catch (e) {
      throw AbsFailure.from(e);
    }
  }

  // --- Phase 1 ---

  /// The signed-in user with permissions, progress and bookmarks. `POST`,
  /// not `GET` (docs/abs-api.md section 18, item 1).
  Future<Map<String, Object?>> authorize() async {
    final data = await post<Map<String, Object?>>('/api/authorize');
    final user = data['user'];
    if (user is Map<String, Object?>) user.remove('token');
    return data;
  }

  void close() => dio.close(force: true);
}
