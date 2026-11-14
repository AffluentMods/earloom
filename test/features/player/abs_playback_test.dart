// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/ui/cover_image.dart';
import 'package:earloom/features/player/abs_playback.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/abs/$name.json').readAsStringSync()) as Map<String, Object?>;

/// Records calls instead of talking to a server.
class FakeApi implements AbsPlaybackApi {
  FakeApi(this.session, {this.serverUpdatedAt});
  final Map<String, Object?> session;
  final DateTime? serverUpdatedAt;
  final syncs = <Map<String, Object?>>[];
  final closes = <Map<String, Object?>>[];
  Object? failSyncWith;
  bool disposed = false;
  int finished = 0;
  Map<String, Object?>? openBody;

  @override
  Map<String, String> get customHeaders => const {'X-Proxy': 'demo'};

  @override
  Future<Map<String, Object?>> openSession(
    String itemId, {
    String? episodeId,
    required Map<String, Object?> body,
  }) async {
    openBody = body;
    return session;
  }

  @override
  Future<void> sync(String sessionId, Map<String, Object?> body) async {
    final fail = failSyncWith;
    if (fail != null) throw fail;
    syncs.add(body);
  }

  @override
  Future<void> close(String sessionId, Map<String, Object?> body) async => closes.add(body);

  @override
  Future<void> markFinished(String itemId, {String? episodeId}) async => finished++;

  @override
  Future<DateTime?> progressUpdatedAt(String itemId, {String? episodeId}) async => serverUpdatedAt;

  @override
  Uri url(String path) => Uri.parse('https://books.example.com/abs$path');

  @override
  void dispose() => disposed = true;
}

const _device = PlaybackDevice(deviceId: 'device-1', clientVersion: '0.1.0', model: 'Demo');

void main() {
  test('a direct play session streams from the public session route, never with a token', () async {
    final session = _fixture('session_play_book_multifile');
    final api = FakeApi(session);
    final ref = ItemRef(const AbsSource('a1'), session['libraryItemId']! as String);
    final (book, decision) = await AbsSessionStarter(api: api, device: _device).start(ref);
    expect(book.tracks, hasLength(8));
    expect(book.tracks.first.uri.toString(), 'https://books.example.com/abs/public/session/${session['id']}/track/1');
    expect(book.tracks.every((t) => !t.uri.query.contains('token')), isTrue);
    expect(book.tracks.first.headers, {'X-Proxy': 'demo'});
    expect(book.tracks[1].start, const Duration(seconds: 240));
    expect(book.chapters, hasLength(8));
    expect(book.title, "The Clockmaker's Tide");
    expect(book.cover, isA<NetworkCover>());
    expect(decision.position, Duration.zero);
    final body = api.openBody!;
    expect(body['supportedMimeTypes'], contains('audio/mpeg'));
    expect((body['deviceInfo']! as Map)['deviceId'], 'device-1');
    expect((body['deviceInfo']! as Map)['clientName'], 'Earloom');
  });

  test('a transcode session plays its HLS playlist', () async {
    final session = _fixture('session_play_book_transcode_hls');
    final api = FakeApi(session);
    final ref = ItemRef(const AbsSource('a1'), session['libraryItemId']! as String);
    final (book, _) = await AbsSessionStarter(api: api, device: _device).start(ref);
    expect(book.tracks.single.uri.path, endsWith('/output.m3u8'));
  });

  test('a newer position on this phone wins over an older server one', () async {
    final session = {..._fixture('session_play_book_m4b'), 'currentTime': 100};
    final api = FakeApi(session, serverUpdatedAt: DateTime(2026, 11, 1));
    final ref = ItemRef(const AbsSource('a1'), session['libraryItemId']! as String);
    final (_, decision) = await AbsSessionStarter(
      api: api,
      device: _device,
      localPosition: (_) async => PositionStamp(const Duration(seconds: 900), DateTime(2026, 11, 2)),
    ).start(ref);
    expect(decision.position, const Duration(seconds: 900));
  });

  test('a far newer server position wins with an undo', () async {
    final session = {..._fixture('session_play_book_m4b'), 'currentTime': 1500};
    final api = FakeApi(session, serverUpdatedAt: DateTime(2026, 11, 3));
    final ref = ItemRef(const AbsSource('a1'), session['libraryItemId']! as String);
    final (_, decision) = await AbsSessionStarter(
      api: api,
      device: _device,
      localPosition: (_) async => PositionStamp(const Duration(seconds: 100), DateTime(2026, 11, 2)),
    ).start(ref);
    expect((decision.position, decision.fromOtherDevice), (const Duration(seconds: 1500), true));
  });

  group('AbsProgressSink', () {
    test('listening time that failed to send goes out with the next sync', () async {
      final api = FakeApi(const {});
      final sink = AbsProgressSink(api: api, sessionId: 's1', itemId: 'i1');
      api.failSyncWith = const AbsUnreachable('offline');
      await sink.report(position: const Duration(seconds: 30), listened: const Duration(seconds: 15), isPlaying: true);
      api.failSyncWith = null;
      await sink.report(position: const Duration(seconds: 45), listened: const Duration(seconds: 15), isPlaying: true);
      expect(api.syncs.single, {'currentTime': 45.0, 'timeListened': 30.0});
      await sink.close(position: const Duration(seconds: 50));
      expect(api.closes.single['timeListened'], 0.0);
      expect(api.disposed, isTrue);
      expect(AbsProgressSink.isOwnSession('s1'), isTrue);
    });

    test('a session the server forgot is not synced again', () async {
      final api = FakeApi(const {});
      final sink = AbsProgressSink(api: api, sessionId: 's2', itemId: 'i1');
      api.failSyncWith = const AbsHttpError(404, 'Not Found');
      await sink.report(position: const Duration(seconds: 30), listened: const Duration(seconds: 15), isPlaying: true);
      api.failSyncWith = null;
      await sink.report(position: const Duration(seconds: 45), listened: const Duration(seconds: 15), isPlaying: true);
      await sink.close(position: const Duration(seconds: 45));
      expect(api.syncs, isEmpty);
      expect(api.closes, isEmpty);
    });
  });
}
