// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/library/models.dart';
import '../../core/library/source_id.dart';
import '../../core/net/abs_client.dart';
import '../../core/net/abs_errors.dart';
import '../../core/sync/outbox.dart';
import '../accounts/data/account_session.dart';
import '../accounts/data/accounts_repository.dart' show AccountRowX;
import '../downloads/data/offline_providers.dart' show syncSchedulerProvider;
import '../local_library/data/providers.dart';

/// Bookmarks for any source. Audiobookshelf identifies a bookmark by its
/// item and time, so both sources do (docs/abs-api.md section 6).
abstract interface class BookmarkService {
  Stream<List<Bookmark>> watch(ItemRef ref);

  /// Returns the position actually used (nudged when one already exists
  /// there).
  Future<Duration> add(ItemRef ref, Duration position, String title);
  Future<void> rename(ItemRef ref, Duration position, String title);
  Future<void> delete(ItemRef ref, Duration position);
}

/// Where a new bookmark goes: whole seconds (ABS keys by time), one second
/// later while that second is taken, so two quick taps keep both.
Duration bookmarkSlot(Duration position, Iterable<Duration> taken) {
  var slot = Duration(seconds: position.inSeconds);
  final used = {for (final t in taken) t.inMilliseconds};
  while (used.contains(slot.inMilliseconds)) {
    slot += const Duration(seconds: 1);
  }
  return slot;
}

final bookmarkServiceProvider = Provider<BookmarkService>((ref) {
  final service = _RoutingBookmarks(ref);
  ref.onDispose(service.dispose);
  return service;
});

final bookmarksProvider = StreamProvider.autoDispose.family<List<Bookmark>, ItemRef>(
  (ref, item) => ref.watch(bookmarkServiceProvider).watch(item),
);

class _RoutingBookmarks implements BookmarkService {
  _RoutingBookmarks(this._ref);
  final Ref _ref;
  final _servers = <String, _AbsBookmarks>{};

  Future<_AbsBookmarks> _server(String accountId) async {
    final existing = _servers[accountId];
    if (existing != null) return existing;
    final account = await _ref.read(globalDbProvider).accountById(accountId);
    if (account == null) throw StateError('The server account for this book was removed');
    final client = AbsClient.create(
      accountId: accountId,
      baseUrl: account.baseUrl,
      store: _ref.read(secureStoreProvider),
      refresher: _ref.read(tokenRefresherProvider),
    );
    OutboxQueue? outbox;
    try {
      outbox = OutboxQueue(_ref.read(offlineDbProvider));
    } on Object {
      // No offline database (some tests): changes need the server.
    }
    return _servers[accountId] = _AbsBookmarks(
      client,
      outbox: outbox,
      onQueued: () {
        try {
          _ref.read(syncSchedulerProvider).kick();
        } on Object {
          // Flushed on the next trigger instead.
        }
      },
    );
  }

  @override
  Stream<List<Bookmark>> watch(ItemRef ref) => switch (ref.source) {
    LocalSource() => _ref.read(localLibraryRepositoryProvider).watchBookmarks(ref.itemId),
    AbsSource(:final accountId) => Stream.fromFuture(_server(accountId)).asyncExpand((s) => s.watch(ref)),
  };

  @override
  Future<Duration> add(ItemRef ref, Duration position, String title) async {
    switch (ref.source) {
      case LocalSource():
        final repo = _ref.read(localLibraryRepositoryProvider);
        final existing = await repo.bookmarks(ref.itemId);
        final slot = bookmarkSlot(position, existing.map((b) => b.position));
        await repo.addBookmark(ref.itemId, slot, title);
        return slot;
      case AbsSource(:final accountId):
        return (await _server(accountId)).add(ref, position, title);
    }
  }

  @override
  Future<void> rename(ItemRef ref, Duration position, String title) async {
    switch (ref.source) {
      case LocalSource():
        await _ref.read(localLibraryRepositoryProvider).renameBookmark(ref.itemId, position, title);
      case AbsSource(:final accountId):
        await (await _server(accountId)).rename(ref, position, title);
    }
  }

  @override
  Future<void> delete(ItemRef ref, Duration position) async {
    switch (ref.source) {
      case LocalSource():
        await _ref.read(localLibraryRepositoryProvider).deleteBookmark(ref.itemId, position);
      case AbsSource(:final accountId):
        await (await _server(accountId)).delete(ref, position);
    }
  }

  void dispose() {
    for (final s in _servers.values) {
      s.dispose();
    }
  }
}

/// Server bookmarks, kept in memory and refetched after each change. When
/// the server cannot be reached the change is queued in the outbox and
/// shown right away; it reaches the server when the outbox flushes.
class _AbsBookmarks {
  _AbsBookmarks(this._client, {this.outbox, this.onQueued});
  final AbsClient _client;
  final OutboxQueue? outbox;
  final void Function()? onQueued;
  final _lists = <String, List<Bookmark>>{};
  final _changes = StreamController<String>.broadcast();

  static double _secs(Duration d) => d.inMilliseconds / 1000;
  static Duration _fromSecs(Object? time) => Duration(milliseconds: ((num.tryParse('$time') ?? 0) * 1000).round());

  Stream<List<Bookmark>> watch(ItemRef ref) async* {
    yield await _load(ref);
    await for (final id in _changes.stream) {
      if (id == ref.itemId) yield _lists[id] ?? const [];
    }
  }

  Future<List<Bookmark>> _load(ItemRef ref) async {
    List<Bookmark> list;
    try {
      final json = await _client.get<Map<String, Object?>>('/api/me/bookmarks/${ref.itemId}');
      list = [
        for (final b in ((json['bookmarks'] as List?) ?? const []).cast<Map<String, Object?>>())
          Bookmark(
            ref: ref,
            // Times can come back as strings from older writes: read leniently.
            position: _fromSecs(b['time']),
            title: (b['title'] ?? '').toString(),
            createdAt: DateTime.fromMillisecondsSinceEpoch((b['createdAt'] as num?)?.toInt() ?? 0),
          ),
      ];
    } on AbsUnreachable {
      if (outbox == null) rethrow;
      // Offline: what we had, plus the changes still waiting below.
      list = [...?_lists[ref.itemId]];
    }
    list = await _withPending(ref, list);
    list.sort((a, b) => a.position.compareTo(b.position));
    _lists[ref.itemId] = list;
    _changes.add(ref.itemId);
    return list;
  }

  /// Applies bookmark changes that have not reached the server yet.
  Future<List<Bookmark>> _withPending(ItemRef ref, List<Bookmark> list) async {
    final queue = outbox;
    if (queue == null) return list;
    final result = [...list];
    for (final e in await queue.pendingFor(ref)) {
      final at = _fromSecs(e.payload['time']);
      final title = (e.payload['title'] ?? '').toString();
      switch (e.kind) {
        case OutboxKind.bookmarkAdd:
          result
            ..removeWhere((b) => b.position == at)
            ..add(Bookmark(ref: ref, position: at, title: title, createdAt: e.createdAt));
        case OutboxKind.bookmarkUpdate:
          final i = result.indexWhere((b) => b.position == at);
          if (i >= 0) {
            result[i] = Bookmark(ref: ref, position: at, title: title, createdAt: result[i].createdAt);
          }
        case OutboxKind.bookmarkDelete:
          result.removeWhere((b) => b.position == at);
        default:
          break;
      }
    }
    return result;
  }

  /// Sends [send]; when the server cannot be reached, queues the change
  /// instead. Returns false when it was queued.
  Future<bool> _sendOrQueue(
    ItemRef ref,
    Future<void> Function() send,
    OutboxKind kind,
    Map<String, Object?> body,
  ) async {
    try {
      await send();
      return true;
    } on AbsUnreachable {
      final queue = outbox;
      if (queue == null) rethrow;
      await queue.enqueue(ref, kind, body);
      onQueued?.call();
      return false;
    }
  }

  Future<Duration> add(ItemRef ref, Duration position, String title) async {
    final current = _lists[ref.itemId] ?? await _load(ref);
    final slot = bookmarkSlot(position, current.map((b) => b.position));
    final body = {'time': _secs(slot), 'title': title};
    await _sendOrQueue(
      ref,
      () => _client.post<Object?>('/api/me/item/${ref.itemId}/bookmark', body: body),
      OutboxKind.bookmarkAdd,
      body,
    );
    await _load(ref);
    return slot;
  }

  Future<void> rename(ItemRef ref, Duration position, String title) async {
    final body = {'time': _secs(position), 'title': title};
    await _sendOrQueue(
      ref,
      () => _client.patch<Object?>('/api/me/item/${ref.itemId}/bookmark', body: body),
      OutboxKind.bookmarkUpdate,
      body,
    );
    await _load(ref);
  }

  Future<void> delete(ItemRef ref, Duration position) async {
    final time = position.inMilliseconds % 1000 == 0 ? '${position.inSeconds}' : '${_secs(position)}';
    await _sendOrQueue(
      ref,
      () => _client.delete<Object?>('/api/me/item/${ref.itemId}/bookmark/$time'),
      OutboxKind.bookmarkDelete,
      {'time': _secs(position)},
    );
    await _load(ref);
  }

  void dispose() {
    _client.close();
    unawaited(_changes.close());
  }
}
