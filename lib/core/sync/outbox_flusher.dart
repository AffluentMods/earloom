// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Sends queued changes in order once the server is reachable again, with
/// backoff and a dead-letter state (docs/plan/05-phase4-offline.md 4.7).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/offline_db.dart';
import '../net/abs_client.dart';
import '../net/abs_errors.dart';
import 'outbox.dart';

/// Local sessions go to `/api/session/local-all` this many at a time.
const localSessionBatch = 25;

/// How one attempt ended.
enum _Outcome { sent, retry, dead, unreachable }

class OutboxFlusher {
  OutboxFlusher({
    required this._db,
    required this._clientFor,
    DateTime Function()? clock,
    this._onReachability,
  }) : _clock = clock ?? DateTime.now,
       queue = OutboxQueue(_db, clock: clock);

  final OfflineDb _db;
  final Future<AbsClient> Function(String accountId) _clientFor;
  final DateTime Function() _clock;
  final void Function(String accountId, bool reachable)? _onReachability;
  final OutboxQueue queue;
  bool _running = false;
  bool _again = false;

  /// Sends everything that is due, for [accountId] or for every account.
  /// Triggers: the server is reachable again, app foreground, successful
  /// re-auth, every 5 min in the foreground, and right after something was
  /// queued. A call while a flush runs makes that flush go round once more.
  Future<void> flush({String? accountId}) async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await queue.coalesce(accountId: accountId);
        final accounts = accountId == null ? await queue.accountsWithPending() : {accountId};
        for (final account in accounts) {
          await _flushAccount(account);
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _flushAccount(String accountId) async {
    final due = await queue.dueInOrder(accountId);
    if (due.isEmpty) return;
    final AbsClient client;
    try {
      client = await _clientFor(accountId);
    } on Object catch (e) {
      // The account is gone or broken: nothing can be sent for it now.
      debugPrint('Outbox: no client for an account: $e');
      return;
    }
    try {
      final blocked = <String>{};
      var i = 0;
      while (i < due.length) {
        final entry = due[i];
        if (blocked.contains(entry.itemKey)) {
          i++;
          continue;
        }
        if (entry.kind == OutboxKind.localSession) {
          // A run of sessions goes as one request, in batches.
          final batch = <OutboxEntry>[];
          while (i < due.length && due[i].kind == OutboxKind.localSession && batch.length < localSessionBatch) {
            if (!blocked.contains(due[i].itemKey)) batch.add(due[i]);
            i++;
          }
          final failed = await _sendSessions(client, batch);
          if (failed == null) {
            _onReachability?.call(accountId, false);
            return;
          }
          blocked.addAll(failed);
          continue;
        }
        final outcome = await _attempt(client, entry);
        switch (outcome) {
          case _Outcome.sent:
            await queue.remove(entry.id);
          case _Outcome.dead:
            break;
          case _Outcome.retry:
            blocked.add(entry.itemKey);
          case _Outcome.unreachable:
            // No point trying the rest now: they would all time out.
            _onReachability?.call(accountId, false);
            return;
        }
        i++;
      }
      _onReachability?.call(accountId, true);
    } finally {
      client.close();
    }
  }

  Future<_Outcome> _attempt(AbsClient client, OutboxEntry entry) async {
    try {
      await _send(client, entry);
      return _Outcome.sent;
    } on AbsFailure catch (e) {
      return _failed(entry, e);
    }
  }

  Future<_Outcome> _failed(OutboxEntry entry, AbsFailure e) async {
    switch (e) {
      case AbsUnreachable():
        await queue.backoff(entry.id, error: e.details);
        return _Outcome.unreachable;
      case AbsForbidden():
        await _dead(entry, e.details);
        return _Outcome.dead;
      case AbsHttpError(:final status) when status >= 400 && status < 500 && status != 408:
        await _dead(entry, e.details);
        return _Outcome.dead;
      case AbsUnauthorized() ||
          AbsRateLimited() ||
          AbsHttpError() ||
          AbsUnexpected() ||
          OidcStateMismatch() ||
          AbsCancelled():
        // 401 (sign in again), 429, 5xx: the change is fine, the moment is
        // not. Try again later.
        await queue.backoff(entry.id, error: e.details);
        return _Outcome.retry;
    }
  }

  Future<void> _dead(OutboxEntry entry, String details) async {
    // Logged without the payload: it is the user's data, not a secret, but
    // the details row in Settings is where it belongs.
    debugPrint('Outbox: ${entry.kind.name} refused by the server, kept as a dead letter: $details');
    await queue.deadLetter(entry.id, details);
  }

  static String _progressPath(OutboxEntry e) =>
      e.episodeId == null ? '/api/me/progress/${e.itemId}' : '/api/me/progress/${e.itemId}/${e.episodeId}';

  /// The server's last update for this item, or null when it has none.
  Future<int?> _serverLastUpdate(AbsClient client, OutboxEntry e) async {
    try {
      final json = await client.get<Object?>(_progressPath(e));
      if (json is Map) return (json['lastUpdate'] as num?)?.toInt();
      return null;
    } on AbsHttpError catch (err) {
      if (err.status == 404) return null;
      rethrow;
    }
  }

  Future<void> _send(AbsClient client, OutboxEntry e) async {
    final p = e.payload;
    switch (e.kind) {
      case OutboxKind.progress:
        final updatedAt = (p['updatedAt'] as num).toInt();
        // The server takes the last writer, whatever its age: compare first,
        // so an older offline position never overwrites a newer one from
        // another device.
        final serverAt = await _serverLastUpdate(client, e);
        if (serverAt != null && serverAt > updatedAt) return;
        await client.patch<Object?>(
          _progressPath(e),
          body: {
            'currentTime': p['currentTime'],
            'duration': p['duration'],
            'progress': p['progress'],
            'lastUpdate': updatedAt,
          },
        );
      case OutboxKind.markFinished:
        final at = (p['finishedAt'] as num?)?.toInt() ?? e.createdAt.millisecondsSinceEpoch;
        final serverAt = await _serverLastUpdate(client, e);
        // Restarted on another device after finishing here: leave it.
        if (serverAt != null && serverAt > at) return;
        await client.patch<Object?>(_progressPath(e), body: {'isFinished': true});
      case OutboxKind.bookmarkAdd:
        await client.post<Object?>('/api/me/item/${e.itemId}/bookmark', body: {'time': p['time'], 'title': p['title']});
      case OutboxKind.bookmarkUpdate:
        await client.patch<Object?>(
          '/api/me/item/${e.itemId}/bookmark',
          body: {'time': p['time'], 'title': p['title']},
        );
      case OutboxKind.bookmarkDelete:
        try {
          await client.delete<Object?>('/api/me/item/${e.itemId}/bookmark/${bookmarkTimeSegment(p['time'] as num)}');
        } on AbsHttpError catch (err) {
          // Already gone: that is what we wanted.
          if (err.status != 404) rethrow;
        }
      case OutboxKind.playlistEdit:
        final method = (p['method'] as String? ?? 'POST').toUpperCase();
        final path = p['path'] as String;
        switch (method) {
          case 'DELETE':
            await client.delete<Object?>(path);
          case 'PATCH':
            await client.patch<Object?>(path, body: p['body']);
          default:
            await client.post<Object?>(path, body: p['body']);
        }
      case OutboxKind.localSession:
        throw StateError('Local sessions are sent in batches');
    }
  }

  /// Sends a batch of local sessions. Returns the item keys that must wait
  /// (retry), or null when the server could not be reached.
  Future<Set<String>?> _sendSessions(AbsClient client, List<OutboxEntry> batch) async {
    if (batch.isEmpty) return const {};
    final ids = {for (final e in batch) e.payload['sessionId'] as String: e};
    final rows = {for (final r in await _db.sessionsByIds(ids.keys)) r.id: r};
    // Sessions deleted meanwhile (account removed): drop their entries.
    for (final entry in batch.where((e) => !rows.containsKey(e.payload['sessionId']))) {
      await queue.remove(entry.id);
    }
    if (rows.isEmpty) return const {};
    final sessions = [for (final row in rows.values) localSessionPayload(row)];
    final device = (jsonDecode(rows.values.first.payloadJson) as Map)['deviceInfo'];
    final List<Object?> results;
    try {
      final json = await client.post<Object?>(
        '/api/session/local-all',
        body: {'deviceInfo': ?device, 'sessions': sessions},
      );
      results = (json is Map ? json['results'] as List? : null) ?? const [];
    } on AbsFailure catch (e) {
      final retry = <String>{};
      for (final entry in batch.where((e) => rows.containsKey(e.payload['sessionId']))) {
        final outcome = await _failed(entry, e);
        if (outcome == _Outcome.unreachable) return null;
        if (outcome == _Outcome.retry) retry.add(entry.itemKey);
      }
      return retry;
    }
    final byId = {
      for (final r in results.whereType<Map<Object?, Object?>>())
        if (r['id'] is String) r['id'] as String: r,
    };
    final synced = <String>[];
    final retry = <String>{};
    for (final MapEntry(key: id, value: entry) in ids.entries) {
      if (!rows.containsKey(id)) continue;
      final result = byId[id];
      if (result == null) {
        await queue.backoff(entry.id, error: 'No result for this session');
        retry.add(entry.itemKey);
      } else if (result['success'] == true) {
        synced.add(id);
        await queue.remove(entry.id);
      } else {
        // "Media item not found" and friends: permanent.
        await _dead(entry, 'local-all: ${result['error'] ?? 'refused'}');
      }
    }
    if (synced.isNotEmpty) await _db.markSessionsSynced(synced, _clock().millisecondsSinceEpoch);
    return retry;
  }
}

/// The time part of a bookmark URL: whole seconds without a decimal point,
/// the same as the bookmark service.
String bookmarkTimeSegment(num time) => time == time.roundToDouble() ? '${time.round()}' : '$time';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The local session object `/api/session/local-all` takes
/// (docs/abs-api.md section 10, fixture `session_local_all_request.json`).
Map<String, Object?> localSessionPayload(LocalSessionRow row) {
  final fixed = (jsonDecode(row.payloadJson) as Map).cast<String, Object?>();
  final started = DateTime.fromMillisecondsSinceEpoch(row.startedAt);
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'id': row.id,
    'libraryId': fixed['libraryId'],
    'libraryItemId': row.itemId,
    'episodeId': row.episodeId,
    'mediaType': fixed['mediaType'] ?? (row.episodeId == null ? 'book' : 'podcast'),
    'displayTitle': fixed['displayTitle'],
    'displayAuthor': fixed['displayAuthor'],
    'duration': row.duration,
    'playMethod': 3,
    'mediaPlayer': 'earloom',
    // The day the listening started, on this phone's calendar.
    'date': '${started.year}-${two(started.month)}-${two(started.day)}',
    'dayOfWeek': _weekdays[started.weekday - 1],
    'timeListening': row.timeListened,
    'startTime': row.startTime,
    'currentTime': row.currentTime,
    'startedAt': row.startedAt,
    'updatedAt': row.updatedAt,
    if (fixed['mediaMetadata'] != null) 'mediaMetadata': fixed['mediaMetadata'],
    if (fixed['coverPath'] != null) 'coverPath': fixed['coverPath'],
  };
}
