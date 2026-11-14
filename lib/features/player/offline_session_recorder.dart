// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/db/offline_db.dart';
import '../../core/library/source_id.dart';
import '../../core/sync/outbox.dart';

/// The parts of a local session that do not change while it runs.
final class LocalSessionInfo {
  const LocalSessionInfo({
    required this.duration,
    required this.deviceInfo,
    this.libraryId,
    this.mediaType = 'book',
    this.displayTitle,
    this.displayAuthor,
    this.mediaMetadata,
  });

  final Duration duration;

  /// `PlaybackDevice.toJson()`: sent once per batch as `deviceInfo`.
  final Map<String, Object?> deviceInfo;
  final String? libraryId;
  final String mediaType;
  final String? displayTitle;
  final String? displayAuthor;

  /// A minimal snapshot (title, author, narrator, series line).
  final Map<String, Object?>? mediaMetadata;

  Map<String, Object?> toJson() => {
    'libraryId': libraryId,
    'mediaType': mediaType,
    'displayTitle': displayTitle,
    'displayAuthor': displayAuthor,
    'mediaMetadata': mediaMetadata,
    'deviceInfo': deviceInfo,
  };
}

/// Records listening without a server session, in `local_sessions`
/// (docs/plan/05-phase4-offline.md 4.6). Used by downloaded playback all the
/// time, and by streamed playback from the moment the network goes away.
///
/// A session is opened on the first [record], updated on every report and
/// queued for `/api/session/local-all` when [close]d. Only closed sessions
/// are sent, once, with their final values: the server moves a re-sent
/// session to the day of its new `updatedAt`.
class OfflineSessionRecorder {
  OfflineSessionRecorder({
    required OfflineDb db,
    required this.ref,
    required this.info,
    DateTime Function()? clock,
    String Function()? newId,
    this._onQueued,
  }) : _db = db,
       _outbox = OutboxQueue(db, clock: clock),
       _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4 {
    if (ref.source is! AbsSource) throw ArgumentError('Local sessions are for server items');
  }

  final OfflineDb _db;
  final OutboxQueue _outbox;
  final ItemRef ref;
  final LocalSessionInfo info;
  final DateTime Function() _clock;
  final String Function() _newId;
  final void Function()? _onQueued;

  String? _id;
  Duration _listened = Duration.zero;
  Future<void> _tail = Future.value();

  bool get isOpen => _id != null;

  /// Listening recorded in the open session.
  Duration get listened => _listened;

  static double _secs(Duration d) => d.inMilliseconds / 1000;

  Future<void> _serial(Future<void> Function() step) {
    final next = _tail.then((_) => step());
    _tail = next.catchError((Object _) {});
    return next;
  }

  /// Adds [listened] (real time since the previous call) and moves the
  /// session to [position]. Opens a session when none is open, starting at
  /// [startAt] (default: [position]).
  Future<void> record({required Duration position, required Duration listened, Duration? startAt}) => _serial(() async {
    final now = _clock().millisecondsSinceEpoch;
    final id = _id;
    if (id == null) {
      final newId = _newId();
      _listened = listened;
      await _db.insertSession(
        LocalSessionsCompanion.insert(
          id: newId,
          accountId: (ref.source as AbsSource).accountId,
          itemId: ref.itemId,
          episodeId: Value(ref.episodeId),
          startedAt: now - listened.inMilliseconds,
          updatedAt: now,
          startTime: _secs(startAt ?? position),
          currentTime: _secs(position),
          timeListened: _secs(_listened),
          duration: _secs(info.duration),
          payloadJson: jsonEncode(info.toJson()),
        ),
      );
      _id = newId;
      return;
    }
    _listened += listened;
    await _db.updateSession(
      id,
      LocalSessionsCompanion(
        updatedAt: Value(now),
        currentTime: Value(_secs(position)),
        timeListened: Value(_secs(_listened)),
      ),
    );
  });

  /// Ends the open session and queues it for the server. A session with no
  /// listening time is dropped: the server would ignore it, and progress
  /// goes its own way.
  Future<void> close({Duration? position}) => _serial(() async {
    final id = _id;
    if (id == null) return;
    _id = null;
    final listened = _listened;
    _listened = Duration.zero;
    final now = _clock().millisecondsSinceEpoch;
    if (listened <= Duration.zero) {
      await (_db.delete(_db.localSessions)..where((t) => t.id.equals(id))).go();
      return;
    }
    await _db.updateSession(
      id,
      LocalSessionsCompanion(
        updatedAt: Value(now),
        closedAt: Value(now),
        currentTime: position == null ? const Value.absent() : Value(_secs(position)),
      ),
    );
    await _outbox.enqueue(ref, OutboxKind.localSession, {'sessionId': id});
    _onQueued?.call();
  });

  /// Closes sessions left open by a crash or a kill. Call at start-up,
  /// before anything plays.
  static Future<int> closeOrphans(OfflineDb db, {DateTime Function()? clock}) async {
    final outbox = OutboxQueue(db, clock: clock);
    var closed = 0;
    for (final s in await db.openSessions()) {
      if (s.timeListened <= 0) {
        await (db.delete(db.localSessions)..where((t) => t.id.equals(s.id))).go();
        continue;
      }
      await db.updateSession(s.id, LocalSessionsCompanion(closedAt: Value(s.updatedAt)));
      await outbox.enqueue(
        ItemRef(AbsSource(s.accountId), s.itemId, episodeId: s.episodeId),
        OutboxKind.localSession,
        {'sessionId': s.id},
      );
      closed++;
    }
    return closed;
  }
}
