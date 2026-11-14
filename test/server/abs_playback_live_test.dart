// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Runs against the local dev server (tool/abs-dev). Skipped automatically
// when it is not running or its passwords file is missing.
@Tags(['server'])
library;

import 'dart:io';

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_client.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/player/abs_playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'abs_auth_live_test.dart' show NoEvents, devPassword, devServer, skipReason;

Future<int> _status(Uri url, {Map<String, String> headers = const {}}) async {
  final http = HttpClient();
  try {
    final request = await http.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    http.close();
  }
}

Future<void> main() async {
  final skip = await skipReason();
  setUpAll(() => HttpOverrides.global = null);

  test('open a session, stream a range without a token, sync, close', () async {
    final auth = AbsAuthApi(devServer);
    final login = await auth.login('affluent', devPassword('affluent')!);
    final store = MemorySecureStore();
    await store.writeTokens('live', access: login.accessToken, refresh: login.refreshToken);
    final refresher = TokenRefresher(store: store, events: NoEvents(), apiFor: (_) async => auth);
    final client = AbsClient.create(accountId: 'live', baseUrl: devServer, store: store, refresher: refresher);

    final libraries = await client.get<Map<String, Object?>>('/api/libraries');
    final books = (libraries['libraries']! as List).cast<Map<String, Object?>>().firstWhere(
      (l) => l['mediaType'] == 'book',
    );
    final page = await client.get<Map<String, Object?>>('/api/libraries/${books['id']}/items', query: {'limit': 1});
    final itemId = ((page['results']! as List).first as Map)['id']! as String;

    final api = ClientPlaybackApi(client, const {});
    final starter = AbsSessionStarter(
      api: api,
      device: const PlaybackDevice(deviceId: 'earloom-live-test', clientVersion: 'test'),
    );
    final (book, _) = await starter.start(ItemRef(const AbsSource('live'), itemId));
    expect(book.tracks, isNotEmpty);
    final track = book.tracks.first.uri;
    expect(track.path, contains('/public/session/'));
    expect(await _status(track, headers: {'Range': 'bytes=0-99'}), 206, reason: 'no token, Range honored');

    await book.sink.report(
      position: const Duration(seconds: 42),
      listened: const Duration(seconds: 3),
      isPlaying: true,
    );
    final progress = await client.get<Map<String, Object?>>('/api/me/progress/$itemId');
    expect(progress['currentTime'], 42);

    await book.sink.close(position: const Duration(seconds: 42));
    expect(await _status(track), 404, reason: 'the stream ends with the session');
  }, skip: skip);
}
