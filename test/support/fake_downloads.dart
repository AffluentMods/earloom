// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/downloads/data/download_manager.dart';
import 'package:earloom/features/downloads/data/download_server.dart';
import 'package:earloom/features/downloads/data/download_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory OfflineDb that works inside widget tests (see
/// `openTestGlobalDb`).
Future<OfflineDb> openTestOfflineDb(WidgetTester tester) async {
  final db = OfflineDb(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.runAsync(() => db.allDownloads());
  addTearDown(() => tester.runAsync(db.close));
  return db;
}

/// The background downloader, faked: records what is queued and lets the
/// test play the downloader's part with [emit] and [finish].
class FakeTransport implements DownloadTransport {
  final jobs = <FileJob>[];
  final canceled = <String>[];
  final paused = <String>[];
  final resumed = <String>[];
  final known = <String, FileStatus>{};
  final _events = StreamController<FileEvent>.broadcast();
  final _wifi = StreamController<bool>.broadcast();
  bool canPause = true;
  bool started = false;
  bool? wifiOnly;

  /// Root the fake writes "downloaded" files under (Application Support).
  Directory? support;

  @override
  Stream<FileEvent> get events => _events.stream;

  @override
  Stream<bool> get onWifi => _wifi.stream;

  void setWifi(bool on) => _wifi.add(on);

  void emit(FileEvent event) => _events.add(event);

  /// Writes [bytes] bytes for the job and reports it complete.
  Future<void> finish(FileJob job, {required int bytes}) async {
    final file = File('${support!.path}/${job.directory}/${job.filename}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List(bytes));
    emit(FileStatusEvent(job.taskId, FileStatus.complete));
  }

  @override
  Future<void> start({required bool wifiOnly}) async {
    started = true;
    this.wifiOnly = wifiOnly;
  }

  @override
  Future<bool> enqueue(FileJob job) async {
    jobs.add(job);
    known[job.taskId] = FileStatus.enqueued;
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    return canPause;
  }

  @override
  Future<bool> resume(String taskId) async {
    resumed.add(taskId);
    return true;
  }

  @override
  Future<void> cancel(Iterable<String> taskIds) async {
    canceled.addAll(taskIds);
    for (final id in taskIds) {
      known.remove(id);
    }
  }

  @override
  Future<Map<String, FileStatus>> knownTasks() async => Map.of(known);

  @override
  Future<void> setWifiOnly(bool wifiOnly) async => this.wifiOnly = wifiOnly;

  @override
  Future<void> askNotificationPermission() async {}
}

/// A server that answers from fixtures.
class FakeDownloadServer implements DownloadServer {
  FakeDownloadServer(this.item, {this.coverBytes, this.series = const []});

  final Map<String, Object?> item;
  final Uint8List? coverBytes;
  final List<String> series;
  int refreshes = 0;
  bool refreshOk = true;
  String access = 'access-1';
  bool closed = false;

  @override
  Future<Map<String, Object?>> expandedItem(String itemId, {String? episodeId}) async => item;

  @override
  Future<Uint8List?> cover(String itemId) async => coverBytes;

  @override
  Future<List<String>> seriesItemIds(String libraryId, String seriesId) async => series;

  @override
  Future<Map<String, String>> fileHeaders() async => {'Authorization': 'Bearer $access', 'X-Proxy': 'demo'};

  @override
  Future<bool> refreshAfterUnauthorized() async {
    refreshes++;
    access = 'access-${refreshes + 1}';
    return refreshOk;
  }

  @override
  Uri url(String path) => Uri.parse('https://books.example.com$path');

  @override
  void close() => closed = true;
}

/// Reads a fixture from test/fixtures/abs.
Map<String, Object?> absFixture(String name) =>
    (jsonDecode(File('test/fixtures/abs/$name.json').readAsStringSync()) as Map).cast<String, Object?>();

/// A download manager whose states the test sets directly.
class FakeDownloadManager implements DownloadManager {
  FakeDownloadManager([Map<String, DownloadState>? initial]) : _states = {...?initial};

  final Map<String, DownloadState> _states;
  final _controller = StreamController<Map<String, DownloadState>>.broadcast();
  final calls = <String>[];

  void put(DownloadState state) {
    _states[state.key] = state;
    _controller.add(Map.of(_states));
  }

  @override
  Stream<Map<String, DownloadState>> get states async* {
    yield Map.of(_states);
    yield* _controller.stream;
  }

  @override
  Future<void> enqueueItem(ItemRef ref, {DownloadReason reason = DownloadReason.user, String? title}) async {
    calls.add('enqueue ${ref.key}');
    put(DownloadState(ref: ref, phase: DownloadPhase.queued, title: title ?? ''));
  }

  @override
  Future<int> enqueueSeries(
    SourceId source, {
    required String libraryId,
    required String seriesId,
    String? after,
    int? limit,
    DownloadReason reason = DownloadReason.user,
  }) async {
    calls.add('series $seriesId');
    return 0;
  }

  @override
  Future<void> pause(String key) async => calls.add('pause $key');

  @override
  Future<void> resume(String key) async => calls.add('resume $key');

  @override
  Future<void> cancel(String key) async => calls.add('cancel $key');

  @override
  Future<void> delete(String key) async {
    calls.add('delete $key');
    _states.remove(key);
    _controller.add(Map.of(_states));
  }

  @override
  Future<void> retryFailed() async => calls.add('retryFailed');

  @override
  Future<void> pauseAll() async => calls.add('pauseAll');

  @override
  Future<void> resumeAll() async => calls.add('resumeAll');

  @override
  Future<void> markFinished(String key, DateTime at) async => calls.add('finished $key');

  @override
  Future<void> setWifiOnly(bool value) async => calls.add('wifiOnly $value');
}
