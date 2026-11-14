// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/downloads/data/abs_download_manager.dart';
import 'package:earloom/features/downloads/data/download_manager.dart';
import 'package:earloom/features/downloads/data/download_paths.dart';
import 'package:earloom/features/downloads/data/download_rules.dart';
import 'package:earloom/features/downloads/data/download_transport.dart';
import 'package:earloom/features/downloads/data/downloaded_playback.dart';
import 'package:earloom/features/downloads/data/item_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_downloads.dart';

const _book = ItemRef(AbsSource('a1'), '695b9eb3-1a88-4320-b033-95089797f205');

/// The fixture keeps two of the book's eight files; the other six are
/// copies with their own ino and offset.
Map<String, Object?> _eightTracks(Map<String, Object?> item) {
  final media = (item['media'] as Map).cast<String, Object?>();
  final first = (media['tracks'] as List).first as Map<String, Object?>;
  media['tracks'] = [
    for (var i = 0; i < 8; i++) {...first, 'index': i + 1, 'ino': '${950727 + i}', 'startOffset': 240 * i},
  ];
  return item;
}

void main() {
  late OfflineDb db;
  late Directory support;
  late FakeTransport transport;
  late FakeDownloadServer server;
  late Map<String, Object?> item;
  late List<SnapshotTrack> tracks;
  var taskIds = 0;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = OfflineDb(NativeDatabase.memory());
    support = await Directory.systemTemp.createTemp('earloom_downloads_');
    transport = FakeTransport()..support = support;
    item = _eightTracks(absFixture('item_book_expanded'));
    tracks = ItemSnapshot.parse(item).tracks;
    server = FakeDownloadServer(item, coverBytes: Uint8List.fromList([1, 2, 3]));
    taskIds = 0;
  });
  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

  AbsDownloadManager manager() => AbsDownloadManager(
    db: db,
    transport: transport,
    serverFor: (_) async => server,
    supportDir: () async => support,
    newTaskId: () => 'task-${++taskIds}',
    notificationTexts: (title) => NotificationTexts(
      running: 'Downloading $title',
      progress: '{numFinished} of {numTotal}',
      complete: 'Downloaded $title',
      failed: '$title failed',
    ),
  );

  /// Lets queued event handling finish.
  Future<void> drain(AbsDownloadManager m) async {
    // Events reach the manager a moment after they are sent; then its
    // queue runs them in order before this no-op.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await m.pause('no-such-download');
  }

  Future<DownloadState> stateOf(AbsDownloadManager m) async => (await m.states.first)[_book.key]!;

  Future<void> finishAll(AbsDownloadManager m, {int Function(int index)? size}) async {
    for (final (i, job) in transport.jobs.indexed) {
      transport.emit(FileStatusEvent(job.taskId, FileStatus.running));
      await transport.finish(job, bytes: size?.call(i) ?? tracks[i].size);
    }
    await drain(m);
  }

  test('saves the snapshot and the cover before queueing the files', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book, title: 'Placeholder');
    final snapshot = await db.snapshot(_book.key);
    expect(snapshot, isNotNull);
    expect(snapshot!.coverPath, 'accounts/a1/downloads/${_book.itemId}/cover.img');
    expect(await File('${support.path}/${snapshot.coverPath}').readAsBytes(), [1, 2, 3]);
    final saved = (jsonDecode(snapshot.tracksJson) as List).cast<Map<String, Object?>>();
    expect(saved.first['localPath'], 'accounts/a1/downloads/${_book.itemId}/track_000.mp3');

    expect(transport.jobs, hasLength(8));
    final job = transport.jobs.first;
    expect(job.url.path, '/api/items/${_book.itemId}/file/950727/download');
    expect(job.url.query, isEmpty, reason: 'tokens never go in URLs');
    expect(job.headers, {'Authorization': 'Bearer access-1', 'X-Proxy': 'demo'});
    expect(job.filename, 'track_000.mp3');
    expect(job.displayName, "The Clockmaker's Tide");

    final state = await stateOf(m);
    expect(state.phase, DownloadPhase.queued);
    expect(state.title, "The Clockmaker's Tide");
    expect(state.bytesTotal, tracks.fold<int>(0, (s, t) => s + t.size));
  });

  test('completes when every file has the size the server reported', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    transport.emit(FileProgressEvent(transport.jobs.first.taskId, 0.5));
    await drain(m);
    expect((await stateOf(m)).phase, DownloadPhase.downloading);
    expect((await stateOf(m)).bytesDone, (tracks.first.size * 0.5).round());

    await finishAll(m);
    final state = await stateOf(m);
    expect(state.phase, DownloadPhase.complete);
    expect(state.fraction, 1);
    final playable = DownloadedPlayback(
      db: db,
      supportDir: () async => support,
      deviceInfo: () async => const {},
      directApi: (_) async => null,
    );
    expect(await playable.isPlayable(_book), isTrue);
    final (book, start) = await playable.open(_book);
    expect(book.tracks, hasLength(8));
    expect(book.tracks.first.uri.scheme, 'file');
    expect(book.tracks[1].start, const Duration(seconds: 240));
    expect(book.title, "The Clockmaker's Tide");
    // The progress saved with the download: 144 s.
    expect(start.position, const Duration(seconds: 144));
  });

  test('a file of the wrong size fails the download as incomplete', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    await finishAll(m, size: (i) => i == 3 ? tracks[i].size - 1 : tracks[i].size);
    final state = await stateOf(m);
    expect(state.phase, DownloadPhase.failed);
    expect(state.error, DownloadError.incomplete);
    expect(state.errorDetails, contains('Track 4'));

    // Trying again queues only that file.
    transport.jobs.clear();
    await m.resume(_book.key);
    expect(transport.jobs.map((j) => j.filename), ['track_003.mp3']);
  });

  test('a 401 refreshes the token and queues the rest with new headers', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    final first = transport.jobs.first;
    transport.emit(FileStatusEvent(first.taskId, FileStatus.running));
    await transport.finish(first, bytes: tracks.first.size);
    final second = transport.jobs[1];
    transport.emit(
      FileStatusEvent(second.taskId, FileStatus.failed, httpStatus: 401, error: 'TaskHttpException: Unauthorized'),
    );
    await drain(m);

    expect(server.refreshes, 1);
    final requeued = transport.jobs.skip(8).toList();
    expect(requeued, hasLength(7), reason: 'every file not done yet');
    expect(requeued.every((j) => j.headers['Authorization'] == 'Bearer access-2'), isTrue);
    expect(transport.canceled, hasLength(6), reason: 'the waiting ones with the old token');
    expect((await stateOf(m)).phase, isNot(DownloadPhase.failed));
  });

  test('pause keeps partial files, resume continues them', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    final running = transport.jobs.first;
    transport.emit(FileStatusEvent(running.taskId, FileStatus.running));
    await drain(m);
    await m.pause(_book.key);
    expect(transport.paused, [running.taskId]);
    expect(transport.canceled, hasLength(7), reason: 'not started: nothing to keep');
    expect((await stateOf(m)).phase, DownloadPhase.paused);

    transport.jobs.clear();
    await m.resume(_book.key);
    expect(transport.resumed, [running.taskId]);
    expect(transport.jobs, hasLength(7));
    expect((await stateOf(m)).phase, isNot(DownloadPhase.paused));
  });

  test('delete removes files and snapshot, never listening', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    await finishAll(m);
    await db.insertSession(
      LocalSessionsCompanion.insert(
        id: 's1',
        accountId: 'a1',
        itemId: _book.itemId,
        startedAt: 1,
        updatedAt: 2,
        startTime: 0,
        currentTime: 5,
        timeListened: 5,
        duration: 10,
        payloadJson: '{}',
      ),
    );
    await m.delete(_book.key);
    expect((await m.states.first)[_book.key], isNull);
    expect(await db.snapshot(_book.key), isNull);
    expect(Directory('${support.path}/${DownloadPaths.folderFor(_book)}').existsSync(), isFalse);
    expect(await db.session('s1'), isNotNull);
  });

  test('after a restart, files the downloader lost are queued again', () async {
    final m = manager();
    await m.start();
    await m.enqueueItem(_book);
    await transport.finish(transport.jobs.first, bytes: tracks.first.size);
    await drain(m);
    await m.dispose();

    // The app was killed; the downloader remembers only one task.
    final kept = transport.jobs[1].taskId;
    transport
      ..known.clear()
      ..known[kept] = FileStatus.running
      ..jobs.clear();
    final again = manager();
    await again.start();
    expect(transport.jobs, hasLength(6));
    expect(transport.jobs.map((j) => j.filename), isNot(contains('track_001.mp3')));
  });

  test('no Wi-Fi with Wi-Fi only on shows waiting for Wi-Fi', () async {
    final m = manager();
    await m.start(wifiOnly: true);
    await m.enqueueItem(_book);
    final states = m.states.map((s) => s[_book.key]?.phase).where((p) => p != null);
    final seen = <DownloadPhase?>[];
    final sub = states.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    transport.setWifi(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(seen.first, DownloadPhase.queued);
    expect(seen.last, DownloadPhase.waitingForWifi);
    expect(transport.wifiOnly, isTrue);
  });

  group('rules', () {
    DownloadState done(String id, {DateTime? finished, int bytes = 1000 * 1000 * 1000}) => DownloadState(
      ref: ItemRef(const AbsSource('a1'), id),
      phase: DownloadPhase.complete,
      bytesTotal: bytes,
      finishedAt: finished,
    );
    final now = DateTime(2026, 11, 14);

    test('auto delete removes books finished 7 days ago, never unfinished ones', () {
      final list = [
        done('old', finished: now.subtract(const Duration(days: 8))),
        done('recent', finished: now.subtract(const Duration(days: 2))),
        done('unfinished'),
      ];
      expect(downloadsToRemove(list, const DownloadSettings(autoDeleteFinished: true), now), ['abs:a1|old']);
      expect(downloadsToRemove(list, const DownloadSettings(), now), isEmpty);
    });

    test('the size limit removes the oldest finished books first and stops at the limit', () {
      final list = [
        done('unfinished', bytes: 5 * 1000 * 1000 * 1000),
        done('b', finished: now.subtract(const Duration(days: 1))),
        done('a', finished: now.subtract(const Duration(days: 3))),
        done('c', finished: now),
      ];
      // 8 GB used, limit 6: two oldest finished go.
      expect(downloadsToRemove(list, const DownloadSettings(maxGigabytes: 6), now), ['abs:a1|a', 'abs:a1|b']);
      // Even at a 1 GB limit the unfinished 5 GB book stays.
      expect(downloadsToRemove(list, const DownloadSettings(maxGigabytes: 1), now), [
        'abs:a1|a',
        'abs:a1|b',
        'abs:a1|c',
      ]);
    });
  });
}
