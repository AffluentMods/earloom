// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import '../../../core/util/dev_log.dart';

/// One audio file to fetch in the background.
final class FileJob {
  const FileJob({
    required this.taskId,
    required this.downloadKey,
    required this.url,
    required this.headers,
    required this.directory,
    required this.filename,
    required this.displayName,
    required this.notification,
  });

  final String taskId;

  /// The download (`ItemRef.key`) this file belongs to.
  final String downloadKey;
  final Uri url;

  /// Captured now: background tasks never refresh tokens (only the main
  /// isolate does). A 401 later makes the manager refresh and re-enqueue.
  final Map<String, String> headers;

  /// Relative to Application Support.
  final String directory;
  final String filename;

  /// The book title, for the notification.
  final String displayName;
  final NotificationTexts notification;
}

/// Notification words, from l10n.
final class NotificationTexts {
  const NotificationTexts({
    required this.running,
    required this.progress,
    required this.complete,
    required this.failed,
  });

  final String running;

  /// May contain `{numFinished}` and `{numTotal}`.
  final String progress;
  final String complete;
  final String failed;
}

enum FileStatus { enqueued, running, complete, failed, notFound, canceled, paused, waitingToRetry }

sealed class FileEvent {
  const FileEvent(this.taskId);
  final String taskId;
}

final class FileStatusEvent extends FileEvent {
  const FileStatusEvent(super.taskId, this.status, {this.httpStatus, this.error});
  final FileStatus status;

  /// For failures with an HTTP answer (401, 403, 416...).
  final int? httpStatus;

  /// Technical details. Never contains a header.
  final String? error;
}

final class FileProgressEvent extends FileEvent {
  const FileProgressEvent(super.taskId, this.fraction);
  final double fraction;
}

/// What the download manager needs from the background downloader. Tests
/// use a fake.
abstract interface class DownloadTransport {
  Stream<FileEvent> get events;

  /// Call once at start-up, after listening to [events]: replays what
  /// happened while the app was suspended or killed and reschedules killed
  /// tasks.
  Future<void> start({required bool wifiOnly});
  Future<bool> enqueue(FileJob job);
  Future<bool> pause(String taskId);
  Future<bool> resume(String taskId);
  Future<void> cancel(Iterable<String> taskIds);

  /// The last known status of every task the downloader remembers.
  Future<Map<String, FileStatus>> knownTasks();

  /// Applies the Wi-Fi only setting to queued and running tasks.
  Future<void> setWifiOnly(bool wifiOnly);

  /// Whether the phone is on Wi-Fi (or Ethernet) now, and changes.
  Stream<bool> get onWifi;

  /// Asks once for the notification permission (Android 13+, iOS), so
  /// progress shows outside the app. Downloads work without it.
  Future<void> askNotificationPermission();
}

/// The real transport: the background_downloader plugin.
class BackgroundTransport implements DownloadTransport {
  BackgroundTransport({FileDownloader? downloader}) : _instance = downloader;

  /// All Earloom tasks share one group, so one listener sees them all. The
  /// download a file belongs to is in the task's `metaData`.
  static const group = 'earloom.downloads';

  FileDownloader? _instance;

  /// Created on first use: the plugin starts native work when it is made.
  FileDownloader get _downloader => _instance ??= FileDownloader();
  final _events = StreamController<FileEvent>.broadcast();
  StreamSubscription<TaskUpdate>? _sub;

  @override
  Stream<FileEvent> get events => _events.stream;

  @override
  Stream<bool> get onWifi async* {
    // The plugin already watches connectivity; poll its view of it so no
    // second listener is needed.
    var last = _downloader.isWiFi;
    yield last;
    await for (final _ in Stream<void>.periodic(const Duration(seconds: 5))) {
      final now = _downloader.isWiFi;
      if (now != last) yield last = now;
    }
  }

  @override
  Future<void> start({required bool wifiOnly}) async {
    _sub ??= _downloader.updates.listen(_onUpdate);
    await _downloader.configure(
      globalConfig: [
        // At most two files at once, so at most two books download at the
        // same time and a large queue never floods the network.
        (Config.holdingQueue, (2, null, null)),
        // Large files can exceed the cache quota and then cannot resume.
        (Config.useCacheDir, Config.never),
        (Config.checkAvailableSpace, 200),
      ],
      androidConfig: [
        // Multi-GB books outlive WorkManager's 9 minute limit otherwise.
        (Config.runInForeground, Config.always),
      ],
      // Audio can be tens of GB: never in iCloud backups.
      iOSConfig: [(Config.excludeFromCloudBackup, Config.always)],
    );
    await setWifiOnly(wifiOnly);
    await _downloader.start(autoCleanDatabase: true);
  }

  @override
  Future<bool> enqueue(FileJob job) {
    final task = DownloadTask(
      taskId: job.taskId,
      url: job.url.toString(),
      headers: job.headers,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: job.directory,
      filename: job.filename,
      group: group,
      metaData: job.downloadKey,
      displayName: job.displayName,
      updates: Updates.statusAndProgress,
      retries: 3,
      // Pause and resume, Android 14+ user-initiated transfers (no time
      // limit), and recovery from the 9 minute WorkManager cut-off.
      transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
      notificationConfig: TaskNotificationConfig(
        running: TaskNotification(job.notification.running, job.notification.progress),
        complete: TaskNotification(job.notification.complete, ''),
        error: TaskNotification(job.notification.failed, ''),
        progressBar: true,
        // One notification per book, not one per file.
        groupNotificationId: 'earloom-${job.downloadKey.hashCode.toUnsigned(32)}',
      ),
    );
    return _downloader.enqueue(task);
  }

  Future<DownloadTask?> _task(String taskId) async {
    final task = await _downloader.taskForId(taskId) ?? (await _downloader.database.recordForId(taskId))?.task;
    return task is DownloadTask ? task : null;
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = await _task(taskId);
    return task != null && await _downloader.pause(task);
  }

  @override
  Future<bool> resume(String taskId) async {
    final task = await _task(taskId);
    return task != null && await _downloader.resume(task);
  }

  @override
  Future<void> cancel(Iterable<String> taskIds) async {
    final ids = taskIds.toList();
    if (ids.isEmpty) return;
    await _downloader.cancelTasksWithIds(ids);
    for (final id in ids) {
      await _downloader.database.deleteRecordWithId(id);
    }
  }

  @override
  Future<Map<String, FileStatus>> knownTasks() async {
    final records = await _downloader.database.allRecords(group: group);
    final active = await _downloader.allTaskIds(group: group);
    return {
      for (final r in records) r.taskId: _status(r.status),
      for (final id in active) id: FileStatus.enqueued,
    };
  }

  bool _askedPermission = false;

  @override
  Future<void> askNotificationPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    try {
      final status = await _downloader.permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) await _downloader.permissions.request(PermissionType.notifications);
    } on Object catch (e) {
      devLog('Downloads: notification permission not asked: $e');
    }
  }

  @override
  Future<void> setWifiOnly(bool wifiOnly) async {
    try {
      final want = wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks;
      // Changing it reschedules every task: only when it really changes.
      if (await _downloader.getRequireWiFiSetting() == want) return;
      await _downloader.requireWiFi(want);
    } on Object catch (e) {
      devLog('Downloads: Wi-Fi setting not applied: $e');
    }
  }

  void _onUpdate(TaskUpdate update) {
    if (update.task.group != group) return;
    switch (update) {
      case TaskStatusUpdate():
        final exception = update.exception;
        _events.add(
          FileStatusEvent(
            update.task.taskId,
            _status(update.status),
            httpStatus: exception is TaskHttpException ? exception.httpResponseCode : null,
            error: exception == null ? null : '${exception.exceptionType}: ${exception.description}',
          ),
        );
      case TaskProgressUpdate():
        if (update.progress >= 0) _events.add(FileProgressEvent(update.task.taskId, update.progress));
    }
  }

  static FileStatus _status(TaskStatus status) => switch (status) {
    TaskStatus.enqueued => FileStatus.enqueued,
    TaskStatus.running => FileStatus.running,
    TaskStatus.complete => FileStatus.complete,
    TaskStatus.notFound => FileStatus.notFound,
    TaskStatus.failed => FileStatus.failed,
    TaskStatus.canceled => FileStatus.canceled,
    TaskStatus.waitingToRetry => FileStatus.waitingToRetry,
    TaskStatus.paused => FileStatus.paused,
  };
}
