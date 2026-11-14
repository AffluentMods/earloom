// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/net/abs_client.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/net/token_refresher.dart';
import '../../../core/storage/secure_store.dart';

/// What the download manager needs from one account's server. Tests use a
/// fake.
abstract interface class DownloadServer {
  /// `GET /api/items/:id?expanded=1&include=progress` (docs/abs-api.md 8).
  Future<Map<String, Object?>> expandedItem(String itemId, {String? episodeId});

  /// The cover as bytes, or null when the item has none.
  Future<Uint8List?> cover(String itemId);

  /// The books of a series in sequence order (item ids).
  Future<List<String>> seriesItemIds(String libraryId, String seriesId);

  /// Headers for file requests: the access token (refreshed first when it
  /// expires soon) and the account's custom headers. Only for background
  /// download tasks; never logged.
  Future<Map<String, String>> fileHeaders();

  /// Forces a refresh after a 401. False means the user must sign in again;
  /// throws [AbsUnreachable] or [AbsRateLimited] when it should wait.
  Future<bool> refreshAfterUnauthorized();

  /// An absolute URL on this server.
  Uri url(String path);

  void close();
}

class AbsDownloadServer implements DownloadServer {
  AbsDownloadServer({
    required this.accountId,
    required this.client,
    required this.store,
    required this.refresher,
  });

  final String accountId;
  final AbsClient client;
  final SecureStore store;
  final TokenRefresher refresher;

  @override
  Future<Map<String, Object?>> expandedItem(String itemId, {String? episodeId}) => client.get<Map<String, Object?>>(
    '/api/items/$itemId',
    query: {'expanded': 1, 'include': 'progress', 'episode': ?episodeId},
  );

  @override
  Future<Uint8List?> cover(String itemId) async {
    try {
      final response = await client.dio.getUri<List<int>>(
        client.url('/api/items/$itemId/cover', {'width': 1024, 'format': 'webp'}),
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw AbsFailure.from(e);
    }
  }

  @override
  Future<List<String>> seriesItemIds(String libraryId, String seriesId) async {
    final filter = 'series.${base64Url.encode(utf8.encode(seriesId))}';
    final json = await client.get<Map<String, Object?>>(
      '/api/libraries/$libraryId/items',
      query: {'filter': filter, 'sort': 'sequence', 'minified': 1, 'limit': 200},
    );
    return [
      for (final item in ((json['results'] as List?) ?? const []).whereType<Map<Object?, Object?>>())
        if (item['id'] is String) item['id'] as String,
    ];
  }

  @override
  Future<Map<String, String>> fileHeaders() async {
    try {
      await refresher.refreshIfNeeded(accountId);
    } on AbsFailure {
      // Offline or rate limited: use what is stored, a 401 brings us back.
    }
    final access = await store.readAccess(accountId);
    return {...await store.readCustomHeaders(accountId), 'Authorization': ?(access == null ? null : 'Bearer $access')};
  }

  @override
  Future<bool> refreshAfterUnauthorized() => refresher.refresh(accountId);

  @override
  Uri url(String path) => client.url(path);

  @override
  void close() => client.close();
}
