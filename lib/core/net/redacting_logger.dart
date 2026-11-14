// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only HTTP logger. Tokens, cookies and passwords are replaced with a
/// placeholder before anything is printed, and query strings are dropped.
class RedactingLogger extends Interceptor {
  RedactingLogger({void Function(String line)? sink}) : _sink = sink ?? debugPrint;

  final void Function(String line) _sink;

  static const redacted = '<redacted>';
  static const _secretHeaders = {'authorization', 'x-refresh-token', 'cookie', 'set-cookie'};
  static const _secretFields = {'password', 'accessToken', 'refreshToken', 'token', 'newPassword'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _sink('-> ${options.method} ${_path(options.uri)} ${_headers(options.headers)}${_body(options.data)}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _sink('<- ${response.statusCode} ${_path(response.requestOptions.uri)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _sink('<- ${err.response?.statusCode ?? err.type.name} ${_path(err.requestOptions.uri)}');
    handler.next(err);
  }

  static String _path(Uri uri) => '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';

  @visibleForTesting
  static Map<String, Object?> redactHeaders(Map<String, Object?> headers) => {
    for (final e in headers.entries) e.key: _secretHeaders.contains(e.key.toLowerCase()) ? redacted : e.value,
  };

  @visibleForTesting
  static Object? redactBody(Object? data) {
    if (data is Map) {
      return {
        for (final e in data.entries) e.key: _secretFields.contains(e.key.toString()) ? redacted : redactBody(e.value),
      };
    }
    if (data is List) return data.map(redactBody).toList();
    return data;
  }

  static String _headers(Map<String, Object?> headers) => headers.isEmpty ? '' : '${redactHeaders(headers)}';

  static String _body(Object? data) => data == null ? '' : ' body: ${redactBody(data)}';
}
