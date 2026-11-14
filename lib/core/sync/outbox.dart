// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Queue of changes that could not be sent yet: progress, finished flags,
/// bookmarks, playlist edits, offline sessions (docs/plan/05-phase4-offline.md
/// section 4.7). Stored in OfflineDb so it survives restarts and works for
/// every account, not only the current one.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/offline_db.dart';
import '../library/source_id.dart';

enum OutboxKind { progress, markFinished, bookmarkAdd, bookmarkUpdate, bookmarkDelete, playlistEdit, localSession }

/// Outbox row states.
abstract final class OutboxState {
  static const pending = 'pending';

  /// The server refused the change for good (a 4xx other than 401). Kept
  /// for the details row, never retried.
  static const dead = 'dead';
}

/// Waits after the 1st, 2nd, 3rd and later failures.
const outboxBackoff = [Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 10), Duration(hours: 1)];

Duration backoffAfter(int attempts) => outboxBackoff[(attempts - 1).clamp(0, outboxBackoff.length - 1)];

/// One queued change, decoded.
final class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.itemId,
    this.episodeId,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
    required this.dead,
  });

  factory OutboxEntry.fromRow(OutboxRow row) => OutboxEntry(
    id: row.id,
    accountId: row.accountId,
    kind: OutboxKind.values.firstWhere((k) => k.name == row.kind, orElse: () => OutboxKind.playlistEdit),
    itemId: row.itemId,
    episodeId: row.episodeId,
    payload: (jsonDecode(row.payloadJson) as Map).cast<String, Object?>(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    attempts: row.attempts,
    nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(row.nextAttemptAt),
    lastError: row.lastError,
    dead: row.state == OutboxState.dead,
  );

  final int id;
  final String accountId;
  final OutboxKind kind;
  final String itemId;
  final String? episodeId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime nextAttemptAt;
  final String? lastError;
  final bool dead;

  /// Changes to the same item are sent in the order they were made.
  String get itemKey => episodeId == null ? itemId : '$itemId|$episodeId';
}

/// How many changes wait, and how many could not be sent at all.
final class OutboxCounts {
  const OutboxCounts({this.pending = 0, this.dead = 0});
  final int pending;
  final int dead;
}

/// Reads and writes the outbox table.
class OutboxQueue {
  OutboxQueue(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final OfflineDb _db;
  final DateTime Function() _clock;

  Future<int> enqueue(ItemRef ref, OutboxKind kind, Map<String, Object?> payload) async {
    final source = ref.source;
    if (source is! AbsSource) throw ArgumentError('Only server items go through the outbox');
    final now = _clock().millisecondsSinceEpoch;
    if (kind == OutboxKind.progress) {
      // Only the newest position matters: drop the older one right away so
      // hours offline do not pile up rows.
      await (_db.delete(_db.outbox)..where(
            (t) =>
                t.accountId.equals(source.accountId) &
                t.itemId.equals(ref.itemId) &
                (ref.episodeId == null ? t.episodeId.isNull() : t.episodeId.equals(ref.episodeId!)) &
                t.kind.equals(OutboxKind.progress.name) &
                t.state.equals(OutboxState.pending),
          ))
          .go();
    }
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            accountId: source.accountId,
            kind: kind.name,
            itemId: ref.itemId,
            episodeId: Value(ref.episodeId),
            payloadJson: jsonEncode(payload),
            createdAt: now,
            nextAttemptAt: Value(now),
          ),
        );
  }

  /// Keeps only the newest pending progress row per item: only the newest
  /// position matters, and it stays where it is in the order.
  Future<void> coalesce({String? accountId}) async {
    final rows =
        await (_db.select(_db.outbox)
              ..where(
                (t) =>
                    t.kind.equals(OutboxKind.progress.name) &
                    t.state.equals(OutboxState.pending) &
                    (accountId == null ? const Constant(true) : t.accountId.equals(accountId)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .get();
    final seen = <String>{};
    final drop = <int>[];
    for (final row in rows) {
      final key = '${row.accountId}|${row.itemId}|${row.episodeId ?? ''}';
      if (!seen.add(key)) drop.add(row.id);
    }
    if (drop.isNotEmpty) await (_db.delete(_db.outbox)..where((t) => t.id.isIn(drop))).go();
  }

  /// Pending entries of [accountId] that may be sent now, oldest first. An
  /// entry waits while an older entry for the same item is still waiting
  /// for its retry, so changes to one item never overtake each other.
  Future<List<OutboxEntry>> dueInOrder(String accountId) async {
    final now = _clock();
    final rows = await pending(accountId);
    final blocked = <String>{};
    final due = <OutboxEntry>[];
    for (final e in rows) {
      if (blocked.contains(e.itemKey)) continue;
      if (e.nextAttemptAt.isAfter(now)) {
        blocked.add(e.itemKey);
        continue;
      }
      due.add(e);
    }
    return due;
  }

  Future<List<OutboxEntry>> pending(String accountId) async {
    final rows =
        await (_db.select(_db.outbox)
              ..where((t) => t.accountId.equals(accountId) & t.state.equals(OutboxState.pending))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(OutboxEntry.fromRow).toList();
  }

  /// Pending changes for one item, oldest first (for showing offline
  /// bookmark edits before they reach the server).
  Future<List<OutboxEntry>> pendingFor(ItemRef ref) async {
    final source = ref.source;
    if (source is! AbsSource) return const [];
    final rows =
        await (_db.select(_db.outbox)
              ..where(
                (t) =>
                    t.accountId.equals(source.accountId) &
                    t.itemId.equals(ref.itemId) &
                    t.state.equals(OutboxState.pending),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(OutboxEntry.fromRow).toList();
  }

  /// Accounts with pending entries.
  Future<Set<String>> accountsWithPending() async {
    final query = _db.selectOnly(_db.outbox, distinct: true)
      ..addColumns([_db.outbox.accountId])
      ..where(_db.outbox.state.equals(OutboxState.pending));
    return {for (final row in await query.get()) row.read(_db.outbox.accountId)!};
  }

  /// When the next entry of any account becomes due, if any.
  Future<DateTime?> nextDueAt() async {
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([_db.outbox.nextAttemptAt.min()])
      ..where(_db.outbox.state.equals(OutboxState.pending));
    final value = (await query.getSingle()).read(_db.outbox.nextAttemptAt.min());
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> remove(int id) => (_db.delete(_db.outbox)..where((t) => t.id.equals(id))).go();

  /// Counts a failed attempt and schedules the next one: 30 s, 2 min,
  /// 10 min, then every hour.
  Future<void> backoff(int id, {String? error}) async {
    final row = await (_db.select(_db.outbox)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final attempts = row.attempts + 1;
    final next = _clock().add(backoffAfter(attempts));
    await (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(next.millisecondsSinceEpoch),
        lastError: Value(error ?? row.lastError),
      ),
    );
  }

  /// The server refused this change: keep it for the details, never retry.
  Future<void> deadLetter(int id, String error) => (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
    OutboxCompanion(
      state: const Value(OutboxState.dead),
      lastError: Value(error),
      attempts: const Value.absent(),
    ),
  );

  Future<List<OutboxEntry>> deadEntries() async {
    final rows =
        await (_db.select(_db.outbox)
              ..where((t) => t.state.equals(OutboxState.dead))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<void> discardDead() => (_db.delete(_db.outbox)..where((t) => t.state.equals(OutboxState.dead))).go();

  Stream<OutboxCounts> watchCounts() {
    return _db.select(_db.outbox).watch().map((rows) {
      var pending = 0, dead = 0;
      for (final r in rows) {
        r.state == OutboxState.dead ? dead++ : pending++;
      }
      return OutboxCounts(pending: pending, dead: dead);
    });
  }
}
