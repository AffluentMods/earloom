// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What a fake server answers.
final class FakeResponse {
  const FakeResponse(this.status, [this.body, this.headers = const {}]);

  /// A JSON answer.
  factory FakeResponse.json(int status, Object? body, [Map<String, List<String>> headers = const {}]) =>
      FakeResponse(status, jsonEncode(body), {
        'content-type': ['application/json'],
        ...headers,
      });

  final int status;
  final String? body;
  final Map<String, List<String>> headers;
}

/// A dio adapter that answers from a handler, for tests without a network.
/// Throw a [DioException] (or any error) from the handler to simulate a
/// network failure.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Future<FakeResponse> Function(RequestOptions request) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final answer = await handler(options);
    return ResponseBody.fromString(answer.body ?? '', answer.status, headers: answer.headers);
  }

  @override
  void close({bool force = false}) {}
}

/// A dio client whose every request goes to [handler].
(Dio, FakeHttpAdapter) fakeDio(Future<FakeResponse> Function(RequestOptions request) handler) {
  final adapter = FakeHttpAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  return (dio, adapter);
}

/// A network failure as dio reports it.
DioException connectionError(RequestOptions request) =>
    DioException.connectionError(requestOptions: request, reason: 'Connection refused');

/// An unsigned JWT that expires at [exp], for refresh timing tests.
String fakeJwt({required DateTime exp, String type = 'access', String id = '1'}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'type': type, 'jti': id, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}
