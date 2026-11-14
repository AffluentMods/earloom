// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/db/global_db.dart';
import '../../core/library/source_id.dart';
import '../../core/net/abs_client.dart';
import '../accounts/data/account_session.dart';
import '../accounts/data/accounts_repository.dart' show AccountRowX;
import '../local_library/data/providers.dart';
import 'abs_playback.dart';
import 'audio_backend.dart';
import 'player_engine.dart';
import 'player_prefs.dart';
import 'progress_resolver.dart';

/// The platform player. Tests override it with a fake.
final audioBackendProvider = Provider<AudioBackend>((ref) => JustAudioBackend());

final playerStoreProvider = Provider<PlayerStore>((ref) => SettingsPlayerStore(ref.watch(globalDbProvider)));

/// The random id this install sends to servers as `deviceId`, made once.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(globalDbProvider);
  final existing = await db.readSetting(SettingKeys.deviceId);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await db.writeSetting(SettingKeys.deviceId, id);
  return id;
});

/// Turns any [ItemRef] into a playable book: local books from the On this
/// device library, server books through a new playback session.
final bookResolverProvider = Provider<BookResolver>((ref) {
  return (ItemRef item, {Duration? startAt}) async {
    switch (item.source) {
      case LocalSource():
        final book = await ref.read(localLibraryRepositoryProvider).playable(item.itemId);
        return (book, StartDecision(startAt ?? book.startPosition));
      case AbsSource(:final accountId):
        final db = ref.read(globalDbProvider);
        final account = await db.accountById(accountId);
        if (account == null) throw StateError('The server account for this book was removed');
        final store = ref.read(secureStoreProvider);
        final headers = await store.readCustomHeaders(accountId);
        // A client of its own, so the book keeps playing (and syncing) when
        // the user switches to another account.
        final client = AbsClient.create(
          accountId: accountId,
          baseUrl: account.baseUrl,
          store: store,
          refresher: ref.read(tokenRefresherProvider),
        );
        final device = await PlaybackDevice.current(await ref.read(deviceIdProvider.future));
        final playerStore = ref.read(playerStoreProvider);
        final starter = AbsSessionStarter(
          api: ClientPlaybackApi(client, headers),
          device: device,
          localPosition: (r) async {
            final last = await playerStore.loadLast();
            return last != null && last.ref == r ? PositionStamp(last.position, last.savedAt) : null;
          },
        );
        try {
          return await starter.start(item, startAt: startAt);
        } on Object {
          client.close();
          rethrow;
        }
    }
  };
});

/// The one player engine. Restores the last book (paused) on creation.
final playerEngineProvider = Provider<PlayerEngine>((ref) {
  final engine = PlayerEngine(
    backend: ref.watch(audioBackendProvider),
    store: ref.watch(playerStoreProvider),
    resolver: (item, {startAt}) => ref.read(bookResolverProvider)(item, startAt: startAt),
  );
  unawaited(engine.restore());
  ref.onDispose(engine.dispose);
  return engine;
});

/// The current player state. Watch with `select` for the parts you show.
final playerProvider = NotifierProvider<PlayerState, PlayerSnapshot>(PlayerState.new);

class PlayerState extends Notifier<PlayerSnapshot> {
  @override
  PlayerSnapshot build() {
    final engine = ref.watch(playerEngineProvider);
    final sub = engine.snapshots.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return engine.value;
  }
}

/// One-time player events for snackbars.
final playerNoticesProvider = StreamProvider<PlayerNotice>((ref) => ref.watch(playerEngineProvider).notices);

/// The player settings, live.
final playerPrefsProvider = NotifierProvider<PlayerPrefsState, PlayerPrefs>(PlayerPrefsState.new);

class PlayerPrefsState extends Notifier<PlayerPrefs> {
  @override
  PlayerPrefs build() {
    final engine = ref.watch(playerEngineProvider);
    unawaited(ref.read(playerStoreProvider).loadPrefs().then((p) => state = p));
    return engine.prefs;
  }

  Future<void> update(PlayerPrefs Function(PlayerPrefs) change) async {
    final next = change(state);
    state = next;
    await ref.read(playerEngineProvider).updatePrefs(next);
  }
}

/// True when [ref] is the loaded book.
bool isCurrent(PlayerSnapshot s, ItemRef ref) => s.now?.ref == ref;
