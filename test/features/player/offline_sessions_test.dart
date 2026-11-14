// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/sync/outbox.dart';
import 'package:earloom/features/downloads/data/downloaded_playback.dart';
import 'package:earloom/features/player/abs_playback.dart';
import 'package:earloom/features/player/offline_session_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

const _book = ItemRef(AbsSource('a1'), 'i1');
const _info = LocalSessionInfo(
  duration: Duration(minutes: 32),
  deviceInfo: {'deviceId': 'demo-device', 'clientName': 'Earloom', 'clientVersion': '0.1.0'},
  libraryId: 'lib1',
  displayTitle: "The Clockmaker's Tide",
  displayAuthor: 'Mara Ellison',
);

/// A server session that can drop off the network.
class FakePlaybackApi implements AbsPlaybackApi {
  bool online = true;
  bool forgotten = false;
  final syncs = <Map<String, Object?>>[];
  final closes = <Map<String, Object?>>[];
  int finishedCalls = 0;

  void _check() {
    if (!online) throw const AbsUnreachable('connectionError: Connection refused');
    if (forgotten) throw const AbsHttpError(404, 'HTTP 404 Not Found');
  }

  @override
  Future<void> sync(String sessionId, Map<String, Object?> body) async {
    _check();
    syncs.add(body);
  }

  @override
  Future<void> close(String sessionId, Map<String, Object?> body) async {
    _check();
    closes.add(body);
  }

  @override
  Future<void> markFinished(String itemId, {String? episodeId}) async {
    _check();
    finishedCalls++;
  }

  @override
  Future<Map<String, Object?>> openSession(String itemId, {String? episodeId, required Map<String, Object?> body}) =>
      throw UnimplementedError();

  @override
  Uri url(String path) => Uri.parse('https://books.example.com$path');

  @override
  Map<String, String> get customHeaders => const {};

  @override
  void dispose() {}

  double get secondsSynced =>
      [...syncs, ...closes].fold(0.0, (sum, b) => sum + ((b['timeListened'] as num?)?.toDouble() ?? 0));
}

class FakeDirect implements DirectProgressApi {
  bool online = true;
  final sent = <Map<String, Object?>>[];

  @override
  Future<void> patchProgress(ItemRef ref, Map<String, Object?> body) async {
    if (!online) throw const AbsUnreachable('offline');
    sent.add(body);
  }

  @override
  void dispose() {}
}

void main() {
  late OfflineDb db;
  late DateTime now;
  var ids = 0;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = OfflineDb(NativeDatabase.memory());
    now = DateTime(2026, 11, 14, 9);
    ids = 0;
  });
  tearDown(() => db.close());

  OfflineSessionRecorder recorder() => OfflineSessionRecorder(
    db: db,
    ref: _book,
    info: _info,
    clock: () => now,
    newId: () => 'session-${++ids}',
  );

  Future<double> localSeconds() async =>
      (await db.select(db.localSessions).get()).fold<double>(0, (sum, s) => sum + s.timeListened);

  const tick = Duration(seconds: 15);

  test('a stream that goes offline then online counts every second once', () async {
    final api = FakePlaybackApi();
    final sink = AbsProgressSink(
      api: api,
      sessionId: 'remote',
      itemId: 'i1',
      recorder: recorder,
      startPosition: const Duration(minutes: 10),
      clock: () => now,
    );
    var position = const Duration(minutes: 10);
    Future<void> play() async {
      now = now.add(tick);
      position += tick;
      await sink.report(position: position, listened: tick, isPlaying: true);
    }

    await play(); // online: synced
    api.online = false;
    await play(); // fails: handed to a local session
    await play(); // offline: local
    expect(sink.isOffline, isTrue);
    api.online = true;
    await play(); // recorded locally, then the probe gets through
    expect(sink.isOffline, isFalse);
    await play(); // online again: synced
    await sink.close(position: position);

    // 5 reports of 15 s: 30 s through syncs, 45 s in the local session.
    expect(api.secondsSynced, 30);
    expect(await localSeconds(), 45);
    final session = (await db.select(db.localSessions).get()).single;
    expect(session.startTime, 615, reason: 'starts where the server last heard from us');
    expect(session.closedAt, isNotNull);
    final queued = await OutboxQueue(db).pending('a1');
    expect(queued.single.kind, OutboxKind.localSession);
    expect(queued.single.payload['sessionId'], session.id);
  });

  test('a session the server forgot keeps recording locally until close', () async {
    final api = FakePlaybackApi();
    final sink = AbsProgressSink(api: api, sessionId: 'remote', itemId: 'i1', recorder: recorder, clock: () => now);
    api.forgotten = true;
    await sink.report(position: tick, listened: tick, isPlaying: true);
    await sink.report(position: tick * 2, listened: tick, isPlaying: true);
    await sink.close(position: tick * 2);
    expect(api.secondsSynced, 0);
    expect(await localSeconds(), 30);
  });

  test('finishing offline queues the finished flag', () async {
    final api = FakePlaybackApi()..online = false;
    final queue = OutboxQueue(db, clock: () => now);
    final sink = AbsProgressSink(
      api: api,
      sessionId: 'remote',
      itemId: 'i1',
      queueFinished: (at) => queue.enqueue(_book, OutboxKind.markFinished, {'finishedAt': at.millisecondsSinceEpoch}),
      clock: () => now,
    );
    await sink.finished(position: const Duration(minutes: 32));
    expect((await queue.pending('a1')).single.kind, OutboxKind.markFinished);
  });

  test('downloaded playback records a session and sends progress directly when it can', () async {
    final direct = FakeDirect();
    final queue = OutboxQueue(db, clock: () => now);
    final sink = DownloadedProgressSink(
      ref: _book,
      duration: const Duration(minutes: 32),
      recorder: recorder(),
      outbox: queue,
      api: direct,
      clock: () => now,
    );
    await sink.report(position: const Duration(minutes: 16), listened: tick, isPlaying: true);
    expect(direct.sent.single, {'currentTime': 960.0, 'duration': 1920.0, 'progress': 0.5});
    expect(await queue.pending('a1'), isEmpty);

    direct.online = false;
    now = now.add(tick);
    await sink.report(position: const Duration(minutes: 16, seconds: 15), listened: tick, isPlaying: true);
    final queued = (await queue.pending('a1')).single;
    expect(queued.kind, OutboxKind.progress);
    expect(queued.payload['currentTime'], 975.0);
    expect(queued.payload['updatedAt'], now.millisecondsSinceEpoch);

    await sink.finished(position: const Duration(minutes: 32));
    await sink.close(position: const Duration(minutes: 32));
    final kinds = (await queue.pending('a1')).map((e) => e.kind);
    expect(kinds, [OutboxKind.progress, OutboxKind.localSession, OutboxKind.markFinished]);
    expect(await localSeconds(), 30);
  });

  test('sessions left open by a kill are closed and queued at start-up', () async {
    final r = recorder();
    await r.record(position: tick, listened: tick);
    await recorder().record(position: Duration.zero, listened: Duration.zero);
    expect(await OfflineSessionRecorder.closeOrphans(db), 1);
    final rows = await db.select(db.localSessions).get();
    expect(rows.single.closedAt, isNotNull, reason: 'the empty one is dropped');
    expect((await OutboxQueue(db).pending('a1')).single.kind, OutboxKind.localSession);
  });
}
