// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/db/offline_db.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_errors.dart';
import 'download_manager.dart';
import 'download_paths.dart';
import 'download_server.dart';
import 'download_transport.dart';
import 'item_snapshot.dart';
import '../../../core/util/dev_log.dart';

/// Download row states (`downloads.status`).
abstract final class DownloadStatus {
  static const queued = 'queued';
  static const downloading = 'downloading';
  static const paused = 'paused';
  static const failed = 'failed';
  static const complete = 'complete';
}

/// File row states (`download_files.status`).
abstract final class FileState {
  /// Not with the downloader (never sent, or taken back on pause).
  static const pending = 'pending';
  static const enqueued = 'enqueued';
  static const running = 'running';
  static const paused = 'paused';
  static const complete = 'complete';
  static const failed = 'failed';
}

/// The download manager on top of [DownloadTransport] (background_downloader
/// in the app, a fake in tests).
///
/// - The snapshot (expanded item) and the cover are saved before any audio
///   file is queued; offline playback reads only them.
/// - Each audio file is its own resumable task. Headers are captured when
///   the task is queued; a 401 makes this (main isolate) object refresh the
///   token and queue the remaining files again with fresh headers.
/// - The downloader's holding queue runs at most two files at once, so at
///   most two books download at the same time.
/// - Finished files are checked against the size the server reported.
class AbsDownloadManager implements DownloadManager {
  AbsDownloadManager({
    required this._db,
    required this._transport,
    required this._serverFor,
    required this._supportDir,
    required NotificationTexts Function(String title) notificationTexts,
    this._excludeFromBackup,
    this._wifiOnly = true,
    DateTime Function()? clock,
    String Function()? newTaskId,
  }) : _texts = notificationTexts,
       _clock = clock ?? DateTime.now,
       _newTaskId = newTaskId ?? const Uuid().v4;

  final OfflineDb _db;
  final DownloadTransport _transport;
  final Future<DownloadServer> Function(String accountId) _serverFor;
  final Future<Directory> Function() _supportDir;
  final NotificationTexts Function(String title) _texts;
  final DateTime Function() _clock;
  final String Function() _newTaskId;

  /// Marks a folder as excluded from iCloud backup (iOS).
  final Future<void> Function(String absolutePath)? _excludeFromBackup;

  bool _wifiOnly;
  bool _onWifi = true;
  final _wifiChanges = StreamController<void>.broadcast();
  StreamSubscription<FileEvent>? _eventSub;
  StreamSubscription<bool>? _wifiSub;

  /// Every change goes through this chain, so events and user actions never
  /// interleave halfway.
  Future<void> _tail = Future.value();

  /// 401 refreshes per download since its last finished file.
  final _authRetries = <String, int>{};
  static const _maxAuthRetries = 3;

  int get _now => _clock().millisecondsSinceEpoch;

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<DownloadPaths> _paths() async => DownloadPaths(await _supportDir());

  /// Starts listening to the downloader, replays what happened while the
  /// app was away, and requeues files the downloader lost.
  Future<void> start({bool? wifiOnly}) async {
    if (wifiOnly != null) _wifiOnly = wifiOnly;
    _eventSub ??= _transport.events.listen((e) => unawaited(_locked(() => _onEvent(e))));
    _wifiSub ??= _transport.onWifi.listen((wifi) {
      _onWifi = wifi;
      _wifiChanges.add(null);
    });
    await _transport.start(wifiOnly: _wifiOnly);
    await _locked(_reconcile);
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _wifiSub?.cancel();
    await _wifiChanges.close();
  }

  @override
  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    _wifiChanges.add(null);
    await _transport.setWifiOnly(value);
  }

  // --- States ---

  @override
  Stream<Map<String, DownloadState>> get states {
    late StreamController<Map<String, DownloadState>> controller;
    StreamSubscription<List<DownloadRow>>? rowsSub;
    StreamSubscription<void>? wifiSub;
    List<DownloadRow>? last;
    void emit() {
      if (last != null && !controller.isClosed) controller.add(_map(last!));
    }

    controller = StreamController<Map<String, DownloadState>>(
      onListen: () {
        rowsSub = _db.watchDownloads().listen((rows) {
          last = rows;
          emit();
        }, onError: controller.addError);
        wifiSub = _wifiChanges.stream.listen((_) => emit());
      },
      onCancel: () async {
        await rowsSub?.cancel();
        await wifiSub?.cancel();
      },
    );
    return controller.stream;
  }

  Map<String, DownloadState> _map(List<DownloadRow> rows) => {for (final r in rows) r.key: stateOf(r)};

  /// The UI state of a row.
  DownloadState stateOf(DownloadRow r) {
    final ref = ItemRef(AbsSource(r.accountId), r.itemId, episodeId: r.episodeId);
    final waiting = _wifiOnly && !_onWifi;
    final phase = switch (r.status) {
      DownloadStatus.complete => DownloadPhase.complete,
      DownloadStatus.failed => DownloadPhase.failed,
      DownloadStatus.paused => DownloadPhase.paused,
      DownloadStatus.downloading => waiting ? DownloadPhase.waitingForWifi : DownloadPhase.downloading,
      _ => waiting ? DownloadPhase.waitingForWifi : DownloadPhase.queued,
    };
    DateTime? time(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    return DownloadState(
      ref: ref,
      phase: phase,
      title: r.title,
      author: r.author,
      libraryId: r.libraryId,
      coverPath: r.coverPath,
      bytesDone: r.bytesDone,
      bytesTotal: r.bytesTotal,
      error: r.status == DownloadStatus.failed ? DownloadError.fromName(r.errorCode) ?? DownloadError.other : null,
      errorDetails: r.lastError,
      reason: DownloadReason.values.where((v) => v.name == r.autoReason).firstOrNull ?? DownloadReason.user,
      createdAt: time(r.createdAt),
      completedAt: time(r.completedAt),
      finishedAt: time(r.finishedAt),
    );
  }

  // --- Enqueue ---

  @override
  Future<void> enqueueItem(ItemRef ref, {DownloadReason reason = DownloadReason.user, String? title}) async {
    final source = ref.source;
    if (source is! AbsSource) throw ArgumentError('Only server items can be downloaded');
    final key = ref.key;
    unawaited(_transport.askNotificationPermission());
    final existing = await _db.download(key);
    if (existing != null) {
      if (existing.status != DownloadStatus.complete) await resume(key);
      return;
    }
    await _db.putDownload(
      DownloadsCompanion.insert(
        key: key,
        accountId: source.accountId,
        itemId: ref.itemId,
        episodeId: Value(ref.episodeId),
        title: title ?? '',
        status: DownloadStatus.queued,
        createdAt: _now,
        autoReason: Value(reason == DownloadReason.user ? null : reason.name),
        wifiOnly: Value(_wifiOnly),
      ),
    );
    await _locked(() => _prepare(ref));
  }

  /// Fetches the item, saves the snapshot and cover, creates the file rows
  /// and queues the files.
  Future<void> _prepare(ItemRef ref) async {
    final key = ref.key;
    final accountId = (ref.source as AbsSource).accountId;
    DownloadServer? server;
    try {
      server = await _serverFor(accountId);
      final item = await server.expandedItem(ref.itemId, episodeId: ref.episodeId);
      final snap = ItemSnapshot.parse(item, episodeId: ref.episodeId);
      if (await _db.download(key) == null) return; // Canceled meanwhile.
      final paths = await _paths();
      final folder = DownloadPaths.folderFor(ref);
      await paths.dir(folder).create(recursive: true);
      // Audio can be tens of GB: the whole downloads folder stays out of
      // iCloud backups (the downloader also marks each file).
      await _excludeFromBackup?.call(paths.dir(DownloadPaths.accountFolder(accountId)).path);

      String? coverPath;
      try {
        final bytes = await server.cover(ref.itemId);
        if (bytes != null && bytes.isNotEmpty) {
          coverPath = p.posix.join(folder, DownloadPaths.coverName);
          await paths.file(coverPath).writeAsBytes(bytes, flush: true);
        }
      } on Object catch (e) {
        // The book plays without its cover; the placeholder shows instead.
        devLog('Downloads: cover not saved: $e');
        coverPath = null;
      }

      final tracks = [
        for (final t in snap.tracks) t.withLocalPath(p.posix.join(folder, DownloadPaths.trackName(t.index, t.ext))),
      ];
      await _db.putSnapshot(
        LocalSnapshotsCompanion.insert(
          key: key,
          accountId: accountId,
          itemId: ref.itemId,
          episodeId: Value(ref.episodeId),
          itemJson: jsonEncode(item),
          chaptersJson: jsonEncode([for (final c in snap.chapters) c.toJson()]),
          tracksJson: jsonEncode([for (final t in tracks) t.toJson()]),
          coverPath: Value(coverPath),
          savedAt: _now,
        ),
      );
      await _db.replaceFiles(key, [
        for (final t in tracks)
          DownloadFilesCompanion.insert(
            downloadKey: key,
            trackIndex: t.index,
            ino: t.ino,
            remotePath: '/api/items/${ref.itemId}/file/${t.ino}/download',
            localPath: t.localPath!,
            sizeExpected: t.size,
            status: FileState.pending,
          ),
      ]);
      await _db.updateDownload(
        key,
        DownloadsCompanion(
          title: Value(snap.title),
          author: Value(snap.author),
          libraryId: Value(snap.libraryId),
          coverPath: Value(coverPath),
          bytesTotal: Value(snap.totalBytes),
          bytesDone: const Value(0),
        ),
      );
      await _queueFiles(key, server);
    } on AbsFailure catch (e) {
      await _fail(key, _errorFor(e), e.details);
    } on FileSystemException catch (e) {
      await _fail(key, DownloadError.storage, '${e.message} (${e.osError?.message ?? ''})');
    } on Object catch (e) {
      // The account was removed, or the item made no sense.
      await _fail(key, DownloadError.other, '$e');
    } finally {
      server?.close();
    }
  }

  /// Hands every file that is not done and not with the downloader to the
  /// downloader, with fresh headers.
  Future<void> _queueFiles(String key, DownloadServer server) async {
    final row = await _db.download(key);
    if (row == null) return;
    final headers = await server.fileHeaders();
    for (final f in await _db.filesOf(key)) {
      if (f.status != FileState.pending && f.status != FileState.failed) continue;
      final taskId = _newTaskId();
      await _db.updateFile(
        key,
        f.trackIndex,
        DownloadFilesCompanion(taskId: Value(taskId), status: const Value(FileState.enqueued)),
      );
      final ok = await _transport.enqueue(
        FileJob(
          taskId: taskId,
          downloadKey: key,
          url: server.url(f.remotePath),
          headers: headers,
          directory: p.posix.dirname(f.localPath),
          filename: p.posix.basename(f.localPath),
          displayName: row.title,
          notification: _texts(row.title),
        ),
      );
      if (!ok) {
        await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.failed)));
        await _fail(key, DownloadError.other, 'The downloader did not accept the file');
        return;
      }
    }
    await _db.updateDownload(
      key,
      DownloadsCompanion(
        status: Value(row.bytesDone > 0 ? DownloadStatus.downloading : DownloadStatus.queued),
        lastError: const Value(null),
        errorCode: const Value(null),
      ),
    );
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
    if (source is! AbsSource) return 0;
    final server = await _serverFor(source.accountId);
    final List<String> ids;
    try {
      ids = await server.seriesItemIds(libraryId, seriesId);
    } finally {
      server.close();
    }
    var start = 0;
    if (after != null) {
      final at = ids.indexOf(after);
      if (at >= 0) start = at + 1;
    }
    var added = 0;
    for (final id in ids.skip(start)) {
      if (limit != null && added >= limit) break;
      final ref = ItemRef(source, id);
      if (await _db.download(ref.key) != null) continue;
      await enqueueItem(ref, reason: reason);
      added++;
    }
    return added;
  }

  // --- Controls ---

  @override
  Future<void> pause(String key) => _locked(() async {
    final row = await _db.download(key);
    if (row == null || row.status == DownloadStatus.complete) return;
    await _db.updateDownload(key, const DownloadsCompanion(status: Value(DownloadStatus.paused)));
    for (final f in await _db.filesOf(key)) {
      final taskId = f.taskId;
      if (taskId == null) continue;
      if (f.status == FileState.running) {
        await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.paused)));
        if (await _transport.pause(taskId)) continue;
      }
      if (f.status == FileState.running || f.status == FileState.enqueued) {
        // Not started yet (or cannot pause): take it back, nothing is lost.
        await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
        await _transport.cancel([taskId]);
      }
    }
  });

  @override
  Future<void> resume(String key) => _locked(() => _resume(key));

  Future<void> _resume(String key) async {
    final row = await _db.download(key);
    if (row == null || row.status == DownloadStatus.complete) return;
    final ref = ItemRef(AbsSource(row.accountId), row.itemId, episodeId: row.episodeId);
    final files = await _db.filesOf(key);
    if (files.isEmpty) {
      // Failed before the item details arrived: start over.
      await _db.updateDownload(key, const DownloadsCompanion(status: Value(DownloadStatus.queued)));
      await _prepare(ref);
      return;
    }
    _authRetries.remove(key);
    await _db.updateDownload(
      key,
      DownloadsCompanion(
        status: Value(row.bytesDone > 0 ? DownloadStatus.downloading : DownloadStatus.queued),
        lastError: const Value(null),
        errorCode: const Value(null),
      ),
    );
    for (final f in files.where((f) => f.status == FileState.paused)) {
      await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.enqueued)));
      if (!await _transport.resume(f.taskId!)) {
        await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
      }
    }
    DownloadServer? server;
    try {
      server = await _serverFor(row.accountId);
      await _queueFiles(key, server);
    } on AbsFailure catch (e) {
      await _fail(key, _errorFor(e), e.details);
    } on Object catch (e) {
      await _fail(key, DownloadError.other, '$e');
    } finally {
      server?.close();
    }
  }

  @override
  Future<void> cancel(String key) => _locked(() => _remove(key));

  @override
  Future<void> delete(String key) => _locked(() => _remove(key));

  /// Removes the files, the file rows and the snapshot. Progress, bookmarks,
  /// local sessions and the outbox are not touched.
  Future<void> _remove(String key) async {
    final row = await _db.download(key);
    if (row == null) return;
    final files = await _db.filesOf(key);
    await _db.deleteDownload(key);
    await _transport.cancel([
      for (final f in files)
        if (f.taskId != null && f.status != FileState.complete) f.taskId!,
    ]);
    final ref = ItemRef(AbsSource(row.accountId), row.itemId, episodeId: row.episodeId);
    await _db.deleteSnapshot(key);
    try {
      final dir = (await _paths()).dir(DownloadPaths.folderFor(ref));
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      devLog('Downloads: folder not removed: ${e.message}');
    }
  }

  @override
  Future<void> retryFailed() async {
    for (final row in await _db.allDownloads()) {
      if (row.status == DownloadStatus.failed) await resume(row.key);
    }
  }

  @override
  Future<void> pauseAll() async {
    for (final row in await _db.allDownloads()) {
      if (row.status == DownloadStatus.queued || row.status == DownloadStatus.downloading) await pause(row.key);
    }
  }

  @override
  Future<void> resumeAll() async {
    for (final row in await _db.allDownloads()) {
      if (row.status == DownloadStatus.paused) await resume(row.key);
    }
  }

  @override
  Future<void> markFinished(String key, DateTime at) =>
      _db.updateDownload(key, DownloadsCompanion(finishedAt: Value(at.millisecondsSinceEpoch)));

  // --- Events ---

  Future<void> _onEvent(FileEvent event) async {
    final file = await _db.fileByTask(event.taskId);
    if (file == null) return; // Canceled or deleted: not ours any more.
    final key = file.downloadKey;
    switch (event) {
      case FileProgressEvent(:final fraction):
        if (file.status == FileState.complete) return;
        await _db.updateFile(key, file.trackIndex, DownloadFilesCompanion(progress: Value(fraction)));
        await _updateBytes(key);
        final row = await _db.download(key);
        if (row?.status == DownloadStatus.queued && fraction > 0) {
          await _db.updateDownload(key, const DownloadsCompanion(status: Value(DownloadStatus.downloading)));
        }
      case FileStatusEvent(:final status):
        await _onStatus(file, event, status);
    }
  }

  Future<void> _onStatus(DownloadFileRow file, FileStatusEvent event, FileStatus status) async {
    final key = file.downloadKey;
    final row = await _db.download(key);
    if (row == null) return;
    switch (status) {
      case FileStatus.enqueued || FileStatus.waitingToRetry:
        if (file.status == FileState.running) {
          await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.enqueued)));
        }
      case FileStatus.running:
        if (file.status == FileState.pending) return; // Taken back on pause.
        await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.running)));
        if (row.status == DownloadStatus.queued) {
          await _db.updateDownload(key, const DownloadsCompanion(status: Value(DownloadStatus.downloading)));
        }
      case FileStatus.paused:
        if (file.status != FileState.pending) {
          await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.paused)));
        }
      case FileStatus.canceled:
        if (file.status == FileState.pending || row.status == DownloadStatus.paused) return;
        // Canceled from the notification: keep what is done, let the user
        // resume or delete.
        await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
        await _db.updateDownload(key, const DownloadsCompanion(status: Value(DownloadStatus.paused)));
      case FileStatus.complete:
        await _onFileComplete(file);
      case FileStatus.failed || FileStatus.notFound:
        if (event.httpStatus == 401) {
          await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.failed)));
          await _reauthorize(key);
          return;
        }
        await _db.updateFile(key, file.trackIndex, const DownloadFilesCompanion(status: Value(FileState.failed)));
        final (code, details) = _fileError(event, status);
        await _fail(key, code, details);
    }
  }

  Future<void> _onFileComplete(DownloadFileRow file) async {
    final key = file.downloadKey;
    final paths = await _paths();
    final onDisk = paths.file(file.localPath);
    final size = await onDisk.exists() ? await onDisk.length() : -1;
    if (file.sizeExpected > 0 && size != file.sizeExpected) {
      await _db.updateFile(
        key,
        file.trackIndex,
        DownloadFilesCompanion(status: const Value(FileState.failed), sizeActual: Value(size < 0 ? null : size)),
      );
      await _fail(
        key,
        DownloadError.incomplete,
        'Track ${file.trackIndex + 1}: expected ${file.sizeExpected} bytes, found ${size < 0 ? 'no file' : size}',
      );
      return;
    }
    _authRetries.remove(key);
    await _db.updateFile(
      key,
      file.trackIndex,
      DownloadFilesCompanion(
        status: const Value(FileState.complete),
        sizeActual: Value(size),
        progress: const Value(1),
      ),
    );
    await _updateBytes(key);
    final files = await _db.filesOf(key);
    if (files.every((f) => f.status == FileState.complete)) {
      final row = await _db.download(key);
      await _db.updateDownload(
        key,
        DownloadsCompanion(
          status: const Value(DownloadStatus.complete),
          completedAt: Value(_now),
          bytesDone: Value(row?.bytesTotal ?? 0),
          lastError: const Value(null),
          errorCode: const Value(null),
        ),
      );
    }
  }

  /// A file came back 401: its token expired while it waited. Refresh here
  /// (the main isolate) and queue the remaining files with new headers.
  Future<void> _reauthorize(String key) async {
    final row = await _db.download(key);
    if (row == null || row.status == DownloadStatus.paused) return;
    final tries = (_authRetries[key] ?? 0) + 1;
    _authRetries[key] = tries;
    if (tries > _maxAuthRetries) {
      await _fail(key, DownloadError.auth, 'HTTP 401 after $_maxAuthRetries token refreshes');
      return;
    }
    DownloadServer? server;
    try {
      server = await _serverFor(row.accountId);
      if (!await server.refreshAfterUnauthorized()) {
        await _fail(key, DownloadError.auth, 'HTTP 401, the server asks to sign in again');
        return;
      }
      // Files still waiting carry the old token too: take them back and
      // queue them again with the new one.
      final waiting = [
        for (final f in await _db.filesOf(key))
          if (f.status == FileState.enqueued && f.taskId != null) f,
      ];
      for (final f in waiting) {
        await _db.updateFile(key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
      }
      await _transport.cancel([for (final f in waiting) f.taskId!]);
      await _queueFiles(key, server);
    } on AbsFailure catch (e) {
      await _fail(key, _errorFor(e), e.details);
    } finally {
      server?.close();
    }
  }

  Future<void> _updateBytes(String key) async {
    var done = 0;
    for (final f in await _db.filesOf(key)) {
      done += f.status == FileState.complete ? f.sizeExpected : (f.sizeExpected * f.progress.clamp(0, 1)).round();
    }
    await _db.updateDownload(key, DownloadsCompanion(bytesDone: Value(done)));
  }

  Future<void> _fail(String key, DownloadError code, String details) async {
    if (await _db.download(key) == null) return;
    await _db.updateDownload(
      key,
      DownloadsCompanion(
        status: const Value(DownloadStatus.failed),
        errorCode: Value(code.name),
        lastError: Value(details),
      ),
    );
  }

  static DownloadError _errorFor(AbsFailure e) => switch (e) {
    AbsUnreachable() => DownloadError.network,
    AbsForbidden() => DownloadError.forbidden,
    AbsUnauthorized() => DownloadError.auth,
    AbsHttpError(status: 404) => DownloadError.notFound,
    _ => DownloadError.other,
  };

  static (DownloadError, String) _fileError(FileStatusEvent e, FileStatus status) {
    final details = [if (e.httpStatus != null) 'HTTP ${e.httpStatus}', ?e.error].join(', ');
    if (status == FileStatus.notFound || e.httpStatus == 404) return (DownloadError.notFound, details);
    if (e.httpStatus == 403) return (DownloadError.forbidden, details);
    final error = e.error ?? '';
    if (error.contains('FileSystem')) return (DownloadError.storage, details);
    if (error.contains('Connection') || error.contains('Timeout')) return (DownloadError.network, details);
    return (DownloadError.other, details.isEmpty ? status.name : details);
  }

  // --- Restart ---

  /// After a restart: files the downloader finished or failed while the
  /// app was gone are settled, files it forgot are queued again.
  Future<void> _reconcile() async {
    final known = await _transport.knownTasks();
    for (final row in await _db.allDownloads()) {
      if (row.status == DownloadStatus.complete || row.status == DownloadStatus.failed) continue;
      final files = await _db.filesOf(row.key);
      if (files.isEmpty) {
        if (row.status != DownloadStatus.paused) {
          await _prepare(ItemRef(AbsSource(row.accountId), row.itemId, episodeId: row.episodeId));
        }
        continue;
      }
      var lost = false;
      for (final f in files) {
        final taskId = f.taskId;
        // Paused by the system (not by the user): carry on.
        if (f.status == FileState.paused && row.status != DownloadStatus.paused && taskId != null) {
          await _db.updateFile(row.key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.enqueued)));
          if (!await _transport.resume(taskId)) {
            await _db.updateFile(row.key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
            lost = true;
          }
          continue;
        }
        if (f.status != FileState.enqueued && f.status != FileState.running) continue;
        final status = taskId == null ? null : known[taskId];
        switch (status) {
          case FileStatus.complete:
            await _onFileComplete(f);
          case FileStatus.failed || FileStatus.notFound || FileStatus.canceled || null:
            await _db.updateFile(row.key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.pending)));
            lost = true;
          case FileStatus.paused:
            await _db.updateFile(row.key, f.trackIndex, const DownloadFilesCompanion(status: Value(FileState.paused)));
          case FileStatus.enqueued || FileStatus.running || FileStatus.waitingToRetry:
            break;
        }
      }
      if (lost && row.status != DownloadStatus.paused) {
        DownloadServer? server;
        try {
          server = await _serverFor(row.accountId);
          await _queueFiles(row.key, server);
        } on AbsFailure catch (e) {
          await _fail(row.key, _errorFor(e), e.details);
        } on Object catch (e) {
          await _fail(row.key, DownloadError.other, '$e');
        } finally {
          server?.close();
        }
      }
    }
  }
}
