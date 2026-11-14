// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/sync/outbox.dart';
import 'package:earloom/core/sync/outbox_flusher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_downloads.dart';
import '../../support/fake_http.dart';
import '../../support/test_client.dart';

const _book = ItemRef(AbsSource('a1'), 'i1');
const _other = ItemRef(AbsSource('a1'), 'i2');

void main() {
  late OfflineDb db;
  late DateTime now;
  late OutboxQueue queue;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = OfflineDb(NativeDatabase.memory());
    now = DateTime(2026, 11, 14, 9);
    queue = OutboxQueue(db, clock: () => now);
  });
  tearDown(() => db.close());

  /// A flusher against a fake server; returns the requests it made.
  Future<(OutboxFlusher, List<RequestOptions>)> flusher(
    Future<FakeResponse> Function(RequestOptions r) handler,
  ) async {
    final requests = <RequestOptions>[];
    final flusher = OutboxFlusher(
      db: db,
      clock: () => now,
      clientFor: (accountId) async {
        final (client, _) = await testAbsClient((r) {
          requests.add(r);
          return handler(r);
        }, accountId: accountId);
        return client;
      },
    );
    return (flusher, requests);
  }

  /// Inserts a row as an older app version would have (no coalescing on
  /// write), to test the flush-time coalescing.
  Future<void> rawProgress(ItemRef ref, double at) => db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          accountId: 'a1',
          kind: OutboxKind.progress.name,
          itemId: ref.itemId,
          payloadJson: jsonEncode({'currentTime': at, 'duration': 100, 'progress': at / 100, 'updatedAt': 1}),
          createdAt: 1,
        ),
      );

  group('queue', () {
    test('coalescing keeps only the newest progress per item, in place', () async {
      await rawProgress(_book, 10);
      await queue.enqueue(_book, OutboxKind.bookmarkAdd, {'time': 5, 'title': 'Here'});
      await rawProgress(_book, 20);
      await rawProgress(_other, 7);
      await rawProgress(_book, 30);
      await queue.coalesce();
      final left = await queue.pending('a1');
      expect(left.map((e) => (e.kind, e.itemId, e.payload['currentTime'])), [
        (OutboxKind.bookmarkAdd, 'i1', null),
        (OutboxKind.progress, 'i2', 7),
        (OutboxKind.progress, 'i1', 30),
      ]);
    });

    test('a new progress replaces the queued one at once', () async {
      for (var i = 1; i <= 50; i++) {
        await queue.enqueue(_book, OutboxKind.progress, {'currentTime': i});
      }
      final left = await queue.pending('a1');
      expect(left, hasLength(1));
      expect(left.single.payload['currentTime'], 50);
    });

    test('backoff waits 30 s, 2 min, 10 min, then every hour', () async {
      final id = await queue.enqueue(_book, OutboxKind.markFinished, {});
      final waits = <Duration>[];
      for (var i = 0; i < 6; i++) {
        await queue.backoff(id, error: 'HTTP 503');
        final e = (await queue.pending('a1')).single;
        waits.add(e.nextAttemptAt.difference(now));
      }
      expect(waits, [
        const Duration(seconds: 30),
        const Duration(minutes: 2),
        const Duration(minutes: 10),
        const Duration(hours: 1),
        const Duration(hours: 1),
        const Duration(hours: 1),
      ]);
    });

    test('a waiting entry holds back later changes to the same item only', () async {
      final first = await queue.enqueue(_book, OutboxKind.bookmarkAdd, {'time': 1, 'title': 'a'});
      await queue.enqueue(_other, OutboxKind.bookmarkAdd, {'time': 2, 'title': 'b'});
      await queue.enqueue(_book, OutboxKind.bookmarkDelete, {'time': 1});
      await queue.backoff(first);
      final due = await queue.dueInOrder('a1');
      expect(due.map((e) => e.itemId), ['i2']);
      now = now.add(const Duration(seconds: 31));
      expect((await queue.dueInOrder('a1')).map((e) => (e.itemId, e.kind)), [
        ('i1', OutboxKind.bookmarkAdd),
        ('i2', OutboxKind.bookmarkAdd),
        ('i1', OutboxKind.bookmarkDelete),
      ]);
    });
  });

  group('flusher', () {
    test('sends in order and empties the queue', () async {
      await queue.enqueue(_book, OutboxKind.bookmarkAdd, {'time': 612, 'title': 'Lighthouse'});
      await queue.enqueue(_book, OutboxKind.bookmarkUpdate, {'time': 612, 'title': 'The lighthouse'});
      await queue.enqueue(_book, OutboxKind.bookmarkDelete, {'time': 612.4});
      await queue.enqueue(_book, OutboxKind.markFinished, {'finishedAt': now.millisecondsSinceEpoch});
      final (f, requests) = await flusher((r) async {
        if (r.method == 'GET') return const FakeResponse(404, 'Not Found');
        return const FakeResponse(200, 'OK');
      });
      await f.flush();
      expect(requests.map((r) => '${r.method} ${r.uri.path}'), [
        'POST /api/me/item/i1/bookmark',
        'PATCH /api/me/item/i1/bookmark',
        'DELETE /api/me/item/i1/bookmark/612.4',
        'GET /api/me/progress/i1',
        'PATCH /api/me/progress/i1',
      ]);
      expect(requests.first.data, {'time': 612, 'title': 'Lighthouse'});
      expect(requests.last.data, {'isFinished': true});
      expect(await queue.pending('a1'), isEmpty);
    });

    test('progress never overwrites a newer position from another device', () async {
      await queue.enqueue(_book, OutboxKind.progress, {
        'currentTime': 100,
        'duration': 1920,
        'progress': 0.05,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      await queue.enqueue(_other, OutboxKind.progress, {
        'currentTime': 50,
        'duration': 1920,
        'progress': 0.03,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      final (f, requests) = await flusher((r) async {
        if (r.method == 'GET' && r.uri.path.endsWith('/i1')) {
          final progress = absFixture('me_progress_book');
          return FakeResponse.json(200, {
            ...progress,
            'lastUpdate': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          });
        }
        if (r.method == 'GET') {
          return FakeResponse.json(200, {'lastUpdate': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch});
        }
        return const FakeResponse(200, 'OK');
      });
      await f.flush();
      final patches = requests.where((r) => r.method == 'PATCH').toList();
      expect(patches.map((r) => r.uri.path), ['/api/me/progress/i2']);
      expect(patches.single.data, {
        'currentTime': 50,
        'duration': 1920,
        'progress': 0.03,
        'lastUpdate': now.millisecondsSinceEpoch,
      });
      expect(await queue.pending('a1'), isEmpty);
    });

    test('a 4xx other than 401 is a dead letter; 401 and 5xx wait and retry', () async {
      await queue.enqueue(_book, OutboxKind.bookmarkAdd, {'time': 1, 'title': ''});
      await queue.enqueue(_other, OutboxKind.bookmarkAdd, {'time': 2, 'title': 'b'});
      const third = ItemRef(AbsSource('a1'), 'i3');
      await queue.enqueue(third, OutboxKind.bookmarkAdd, {'time': 3, 'title': 'c'});
      final (f, _) = await flusher((r) async {
        if (r.uri.path.contains('/i1/')) return const FakeResponse(400, 'Invalid title');
        if (r.uri.path.contains('/i2/')) return const FakeResponse(503, 'busy');
        // The token refresh is refused too: sign in again, keep the change.
        return const FakeResponse(401, 'Unauthorized');
      });
      await f.flush();
      final dead = await queue.deadEntries();
      expect(dead.map((e) => e.itemId), ['i1']);
      expect(dead.single.lastError, contains('400'));
      final pending = await queue.pending('a1');
      expect(pending.map((e) => (e.itemId, e.attempts)), [('i2', 1), ('i3', 1)]);

      // Dead letters are never sent again.
      await f.flush();
      expect((await queue.deadEntries()).single.attempts, 0);
    });

    test('an unreachable server stops the flush and keeps everything', () async {
      for (var i = 0; i < 5; i++) {
        await queue.enqueue(ItemRef(const AbsSource('a1'), 'i$i'), OutboxKind.markFinished, {});
      }
      final (f, requests) = await flusher((r) async => throw connectionError(r));
      await f.flush();
      expect(requests, hasLength(1));
      expect(await queue.pending('a1'), hasLength(5));
    });

    test('local sessions go in batches of 25 with the payload the server takes', () async {
      for (var i = 0; i < 30; i++) {
        final id = '11111111-2222-4333-8444-5555555555${i.toString().padLeft(2, '0')}';
        await db.insertSession(
          LocalSessionsCompanion.insert(
            id: id,
            accountId: 'a1',
            itemId: 'i$i',
            startedAt: DateTime(2026, 11, 11, 9).millisecondsSinceEpoch,
            updatedAt: DateTime(2026, 11, 11, 9, 10).millisecondsSinceEpoch,
            startTime: 0,
            currentTime: 200,
            timeListened: 600,
            duration: 360,
            closedAt: const Value(1),
            payloadJson: jsonEncode({
              'libraryId': 'lib1',
              'mediaType': 'book',
              'displayTitle': 'A Field Guide to Quiet Places',
              'displayAuthor': 'Ines Okafor',
              'deviceInfo': {'deviceId': 'demo-device', 'clientName': 'Earloom', 'clientVersion': '0.1.0'},
            }),
          ),
        );
        await queue.enqueue(ItemRef(const AbsSource('a1'), 'i$i'), OutboxKind.localSession, {'sessionId': id});
      }
      final (f, requests) = await flusher((r) async {
        final sessions = ((r.data as Map)['sessions'] as List).cast<Map<String, Object?>>();
        return FakeResponse.json(200, {
          'results': [
            for (final s in sessions)
              s['libraryItemId'] == 'i3'
                  ? {'id': s['id'], 'success': false, 'error': 'Media item not found'}
                  : {'id': s['id'], 'success': true, 'progressSynced': true},
          ],
        });
      });
      await f.flush();
      expect(requests.map((r) => ((r.data as Map)['sessions'] as List).length), [25, 5]);
      expect(requests.every((r) => r.uri.path == '/api/session/local-all'), isTrue);

      // Same keys as the request the server accepted (docs/abs-api.md 10).
      final fixture = absFixture('session_local_all_request');
      final body = requests.first.data as Map<String, Object?>;
      expect(body.keys.toSet(), fixture.keys.toSet());
      final sent = (body['sessions'] as List).first as Map<String, Object?>;
      final expected = ((fixture['sessions'] as List).first as Map).keys.toSet();
      expect(sent.keys.toSet().containsAll(expected), isTrue, reason: '${expected.difference(sent.keys.toSet())}');
      expect(sent['playMethod'], 3);
      expect(sent['timeListening'], 600);
      expect(sent['date'], '2026-11-11');
      expect(sent['dayOfWeek'], 'Wednesday');
      expect((body['deviceInfo'] as Map)['deviceId'], 'demo-device');

      expect(await queue.pending('a1'), isEmpty);
      expect((await queue.deadEntries()).single.itemId, 'i3');
      final synced = await db.select(db.localSessions).get();
      expect(synced.where((s) => s.syncedAt != null), hasLength(29));
    });
  });
}
