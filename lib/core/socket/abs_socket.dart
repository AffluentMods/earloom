// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Something changed on the server. See docs/abs-api.md section 14.
sealed class AbsSocketEvent {
  const AbsSocketEvent();
}

/// Playback progress changed (playback on any device, including echoes of
/// our own session: compare [sessionId]).
final class ProgressUpdated extends AbsSocketEvent {
  const ProgressUpdated({required this.sessionId, required this.progress});
  final String? sessionId;

  /// The raw mediaProgress object.
  final Map<String, Object?> progress;
}

/// The whole user changed: manual progress edits, finished flags,
/// bookmarks. Diff [user]['mediaProgress'] and ['bookmarks'].
final class UserUpdated extends AbsSocketEvent {
  const UserUpdated(this.user);
  final Map<String, Object?> user;
}

/// One or more items were added or changed (full expanded items).
final class ItemsChanged extends AbsSocketEvent {
  const ItemsChanged(this.items, {required this.added});
  final List<Map<String, Object?>> items;
  final bool added;
}

final class ItemRemoved extends AbsSocketEvent {
  const ItemRemoved({required this.itemId, this.libraryId});
  final String itemId;
  final String? libraryId;
}

/// A playlist, collection, series, author or library changed; refresh that
/// kind of list.
final class CatalogChanged extends AbsSocketEvent {
  const CatalogChanged(this.kind);

  /// playlist, collection, series, author or library.
  final String kind;
}

/// The socket connection to one account's server.
///
/// The server checks the token only when `auth` is emitted, so an expired
/// token does not drop a live connection. After every (re)connect `auth` is
/// sent again with a fresh token from [accessToken].
class AbsSocket {
  AbsSocket({required this.baseUrl, required this.accessToken});

  final Uri baseUrl;

  /// Returns a current access token (refreshing first when needed).
  final Future<String?> Function() accessToken;

  final _events = StreamController<AbsSocketEvent>.broadcast();
  final connected = ValueNotifier<bool>(false);
  io.Socket? _socket;

  Stream<AbsSocketEvent> get events => _events.stream;

  /// Connects with the account's custom reverse-proxy [headers].
  void connect({Map<String, String> headers = const {}}) {
    if (_socket != null) return;
    final origin = baseUrl.replace(path: '', query: null);
    final socket = io.io(
      origin.toString(),
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('${baseUrl.path}/socket.io')
          .setExtraHeaders(headers)
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(60000)
          .setRandomizationFactor(0.5)
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) => _authenticate());
    socket.onDisconnect((_) => connected.value = false);
    socket.on('init', (_) => connected.value = true);
    socket.on('user_item_progress_updated', (data) {
      if (data is Map && data['data'] is Map) {
        _events.add(
          ProgressUpdated(
            sessionId: data['sessionId'] as String?,
            progress: Map<String, Object?>.from(data['data'] as Map),
          ),
        );
      }
    });
    socket.on('user_updated', (data) {
      if (data is Map) _events.add(UserUpdated(Map<String, Object?>.from(data)..remove('token')));
    });
    socket.on('item_updated', (data) => _items(data, added: false));
    socket.on('item_added', (data) => _items(data, added: true));
    socket.on('items_updated', (data) => _items(data, added: false));
    socket.on('items_added', (data) => _items(data, added: true));
    socket.on('item_removed', (data) {
      if (data is Map && data['id'] is String) {
        _events.add(ItemRemoved(itemId: data['id'] as String, libraryId: data['libraryId'] as String?));
      }
    });
    for (final kind in ['playlist', 'collection', 'series', 'author', 'library']) {
      for (final verb in ['added', 'updated', 'removed']) {
        socket.on('${kind}_$verb', (_) => _events.add(CatalogChanged(kind)));
      }
    }
    socket.connect();
  }

  /// Sends the current token again, for example after a token rotation.
  Future<void> reauthenticate() => _authenticate();

  Future<void> _authenticate() async {
    final token = await accessToken();
    if (token != null) _socket?.emit('auth', token);
  }

  void _items(Object? data, {required bool added}) {
    final list = data is List ? data : [data];
    final items = [
      for (final i in list)
        if (i is Map) Map<String, Object?>.from(i),
    ];
    if (items.isNotEmpty) _events.add(ItemsChanged(items, added: added));
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    connected.value = false;
  }

  void dispose() {
    disconnect();
    _events.close();
    connected.dispose();
  }
}
