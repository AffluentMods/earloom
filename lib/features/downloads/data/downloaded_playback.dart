// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/db/offline_db.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/sync/outbox.dart';
import '../../../core/ui/cover_image.dart';
import '../../player/offline_session_recorder.dart';
import '../../player/playable.dart';
import '../../player/progress_resolver.dart';
import 'abs_download_manager.dart' show DownloadStatus;
import 'download_paths.dart';
import 'item_snapshot.dart';

/// Sends progress straight to the server while it answers.
abstract interface class DirectProgressApi {
  /// `PATCH /api/me/progress/...` with currentTime, duration and progress.
  Future<void> patchProgress(ItemRef ref, Map<String, Object?> body);
  void dispose();
}

/// Builds playable books from downloads: the snapshot and the files on the
/// phone, never the server (docs/plan/05-phase4-offline.md 4.6).
class DownloadedPlayback {
  DownloadedPlayback({
    required this._db,
    required this._supportDir,
    required this.deviceInfo,
    required this.directApi,
    this.lastPosition,
    this.isOnline,
    this.onQueued,
    this.onFinished,
    this.onProgress,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OfflineDb _db;
  final Future<Directory> Function() _supportDir;
  final DateTime Function() _clock;

  /// `PlaybackDevice.toJson()` of this phone.
  final Future<Map<String, Object?>> Function() deviceInfo;

  /// A client for the account, or null when none can be made.
  final Future<DirectProgressApi?> Function(String accountId) directApi;

  /// Where this phone last was in the book (the player's own record).
  final Future<PositionStamp?> Function(ItemRef ref)? lastPosition;

  /// Whether the account's server is known to be reachable. Unknown counts
  /// as reachable: the send itself finds out.
  final bool Function(String accountId)? isOnline;

  /// Something was queued: a good moment to flush.
  final void Function()? onQueued;

  /// The book was finished (download rules).
  final Future<void> Function(ItemRef ref, DateTime at)? onFinished;

  /// Position updates, for the auto-download of the next book in a series.
  final void Function(ItemRef ref, double fraction)? onProgress;

  /// True when every file of the download is on the phone.
  Future<bool> isPlayable(ItemRef ref) async {
    final row = await _db.download(ref.key);
    if (row == null || row.status != DownloadStatus.complete) return false;
    final snapshot = await _db.snapshot(ref.key);
    if (snapshot == null) return false;
    final support = await _supportDir();
    final paths = DownloadPaths(support);
    for (final f in await _db.filesOf(ref.key)) {
      if (!await paths.file(f.localPath).exists()) return false;
    }
    return true;
  }

  Future<(PlayableBook, StartDecision)> open(ItemRef ref, {Duration? startAt}) async {
    final row = await _db.snapshot(ref.key);
    if (row == null) throw StateError('The download has no saved details');
    final paths = DownloadPaths(await _supportDir());
    final item = (jsonDecode(row.itemJson) as Map).cast<String, Object?>();
    final snap = ItemSnapshot.parse(item, episodeId: ref.episodeId);
    final tracks = [
      for (final t in (jsonDecode(row.tracksJson) as List).cast<Map<String, Object?>>()) SnapshotTrack.fromJson(t),
    ];
    Duration secs(double s) => Duration(milliseconds: (s * 1000).round());
    final chapters = [
      for (final (i, c) in snap.chapters.indexed)
        Chapter(index: i, title: c.title, start: secs(c.start), end: secs(c.end)),
    ];
    final coverPath = row.coverPath == null ? null : paths.file(row.coverPath!).path;
    final duration = tracks.isEmpty ? Duration.zero : secs(tracks.last.startOffset + tracks.last.duration);
    final accountId = (ref.source as AbsSource).accountId;
    final recorder = OfflineSessionRecorder(
      db: _db,
      ref: ref,
      clock: _clock,
      onQueued: onQueued,
      info: LocalSessionInfo(
        duration: duration,
        deviceInfo: await deviceInfo(),
        libraryId: snap.libraryId,
        mediaType: snap.mediaType,
        displayTitle: snap.title,
        displayAuthor: snap.author,
        mediaMetadata: snap.sessionMetadata(),
      ),
    );
    final sink = DownloadedProgressSink(
      ref: ref,
      duration: duration,
      recorder: recorder,
      outbox: OutboxQueue(_db, clock: _clock),
      api: await directApi(accountId),
      isOnline: isOnline == null ? null : () => isOnline!(accountId),
      onQueued: onQueued,
      onFinished: onFinished,
      onProgress: onProgress,
      clock: _clock,
    );
    final isEpisode = ref.episodeId != null;
    final book = PlayableBook(
      ref: ref,
      title: snap.title,
      // An episode shows its show (kept as the series line) as the artist.
      author: isEpisode ? snap.seriesLine ?? snap.author : snap.author,
      narrator: snap.narrator,
      seriesLine: isEpisode ? null : snap.seriesLine,
      tracks: [
        for (final t in tracks)
          PlayableTrack(
            uri: Uri.file(paths.file(t.localPath!).path),
            start: secs(t.startOffset),
            duration: secs(t.duration),
            mimeType: t.mimeType,
          ),
      ],
      chapters: chapters,
      artworkUri: coverPath == null ? null : Uri.file(coverPath),
      cover: coverPath == null ? null : FileCover(coverPath),
      coverKey: '${ref.itemId}-${snap.updatedAt}',
      sink: sink,
    );
    if (startAt != null) return (book, StartDecision(startAt));
    return (book, await _start(ref, snap));
  }

  /// Where to start without asking the server: the newest of this phone's
  /// own record, the last local session, and the progress saved with the
  /// download.
  Future<StartDecision> _start(ItemRef ref, ItemSnapshot snap) async {
    final stamps = <PositionStamp>[];
    final mine = await lastPosition?.call(ref);
    if (mine != null) stamps.add(mine);
    final source = ref.source as AbsSource;
    final sessions =
        await (_db.select(_db.localSessions)..where(
              (t) =>
                  t.accountId.equals(source.accountId) &
                  t.itemId.equals(ref.itemId) &
                  (ref.episodeId == null ? t.episodeId.isNull() : t.episodeId.equals(ref.episodeId!)),
            ))
            .get();
    for (final s in sessions) {
      stamps.add(
        PositionStamp(
          Duration(milliseconds: (s.currentTime * 1000).round()),
          DateTime.fromMillisecondsSinceEpoch(s.updatedAt),
        ),
      );
    }
    PositionStamp? local;
    for (final s in stamps) {
      if (local == null || s.at.isAfter(local.at)) local = s;
    }
    final saved = snap.progressTime == null || snap.isFinished
        ? null
        : PositionStamp(
            Duration(milliseconds: (snap.progressTime! * 1000).round()),
            DateTime.fromMillisecondsSinceEpoch(snap.progressUpdatedAt ?? 0),
          );
    return resolveStart(local: local, server: saved);
  }
}

/// Progress of a downloaded book: always a local session (for listening
/// stats), plus the position straight to the server when it answers, or
/// queued in the outbox when it does not.
class DownloadedProgressSink implements ProgressSink {
  DownloadedProgressSink({
    required this.ref,
    required this.duration,
    required this._recorder,
    required this._outbox,
    this._api,
    this._isOnline,
    this._onQueued,
    this._onFinished,
    this._onProgress,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ItemRef ref;
  final Duration duration;
  final OfflineSessionRecorder _recorder;
  final OutboxQueue _outbox;
  final DirectProgressApi? _api;
  final bool Function()? _isOnline;
  final void Function()? _onQueued;
  final Future<void> Function(ItemRef ref, DateTime at)? _onFinished;
  final void Function(ItemRef ref, double fraction)? _onProgress;
  final DateTime Function() _clock;
  bool _closed = false;

  static double _secs(Duration d) => d.inMilliseconds / 1000;

  Map<String, Object?> _progress(Duration position) {
    final total = _secs(duration);
    return {
      'currentTime': _secs(position),
      'duration': total,
      'progress': total <= 0 ? 0 : (_secs(position) / total).clamp(0.0, 1.0),
    };
  }

  @override
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying}) async {
    if (_closed) return;
    await _recorder.record(position: position, listened: listened);
    if (duration > Duration.zero) _onProgress?.call(ref, position.inMilliseconds / duration.inMilliseconds);
    final body = _progress(position);
    final api = _api;
    if (api != null && (_isOnline?.call() ?? true)) {
      try {
        await api.patchProgress(ref, body);
        return;
      } on AbsFailure {
        // Fall through to the outbox.
      }
    }
    await _outbox.enqueue(ref, OutboxKind.progress, {...body, 'updatedAt': _clock().millisecondsSinceEpoch});
  }

  @override
  Future<void> finished({required Duration position}) async {
    final at = _clock();
    await _recorder.close(position: position);
    await _outbox.enqueue(ref, OutboxKind.markFinished, {'finishedAt': at.millisecondsSinceEpoch});
    _onQueued?.call();
    await _onFinished?.call(ref, at);
  }

  @override
  Future<void> close({required Duration position}) async {
    if (_closed) return;
    _closed = true;
    await _recorder.close(position: position);
    _api?.dispose();
  }
}
