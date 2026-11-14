// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_client.dart';
import '../../../core/net/reachability.dart';
import '../../../core/sync/outbox.dart';
import '../../../core/sync/outbox_flusher.dart';
import '../../accounts/data/account_session.dart';
import '../../accounts/data/accounts_repository.dart' show AccountRowX;
import '../../player/abs_playback.dart';
import '../../player/offline_session_recorder.dart';
import '../../player/player_controller.dart';
import '../../player/progress_resolver.dart';
import 'abs_download_manager.dart';
import 'device_storage.dart';
import 'download_manager.dart';
import 'download_rules.dart';
import 'download_server.dart';
import 'download_transport.dart';
import 'downloaded_playback.dart';
import 'item_snapshot.dart';

/// Application Support. Tests point it at a temporary folder.
final supportDirProvider = Provider<Future<Directory> Function()>((ref) => getApplicationSupportDirectory);

/// Application Support as a path, for showing saved covers.
final supportPathProvider = FutureProvider<String>((ref) async => (await ref.watch(supportDirProvider)()).path);

final deviceStorageProvider = Provider<DeviceStorage>((ref) => const DeviceStorage());

/// Free space on the phone, or null when unknown. Refreshed when the
/// Downloads screen opens.
final freeSpaceProvider = FutureProvider.autoDispose<int?>((ref) async {
  final path = await ref.watch(supportPathProvider.future);
  return ref.watch(deviceStorageProvider).freeBytes(path);
});

/// A new API client for any account, current or not. The caller closes it.
Future<AbsClient> accountClient(Ref ref, String accountId) async {
  final account = await ref.read(globalDbProvider).accountById(accountId);
  if (account == null) throw StateError('The server account was removed');
  return AbsClient.create(
    accountId: accountId,
    baseUrl: account.baseUrl,
    store: ref.read(secureStoreProvider),
    refresher: ref.read(tokenRefresherProvider),
  );
}

/// Forgets everything offline of a removed account: its downloads (and
/// their background tasks), snapshots, local sessions and queued changes.
/// They can no longer reach a server.
Future<void> removeAccountOfflineData(WidgetRef ref, String accountId) async {
  final db = ref.read(offlineDbProvider);
  final manager = ref.read(downloadManagerProvider);
  for (final row in await db.allDownloads()) {
    if (row.accountId == accountId) await manager.delete(row.key);
  }
  await db.deleteAccount(accountId);
}

// --- Reachability ---

final pingerProvider = Provider<Pinger>((ref) => pingServer);

/// Fires when the phone's network changes. Tests override it.
final connectivityChangesProvider = Provider<Stream<void>>(
  (ref) => Connectivity().onConnectivityChanged.map<void>((_) {}).handleError((Object _) {}),
);

/// Whether the current account's server answers.
final reachabilityProvider = Provider<Reachability>((ref) {
  final reach = Reachability(ping: ref.watch(pingerProvider));
  ref.onDispose(reach.dispose);
  String? lastKey;
  ref.listen(currentAccountProvider, (_, next) {
    final account = next.value;
    final key = account == null ? null : '${account.id}|${account.serverUrl}';
    if (key == lastKey) return;
    lastKey = key;
    if (account == null) {
      unawaited(reach.setServer(null));
      return;
    }
    unawaited(() async {
      final headers = await ref.read(secureStoreProvider).readCustomHeaders(account.id);
      if (lastKey == key) await reach.setServer(account.baseUrl, headers: headers);
    }());
  }, fireImmediately: true);
  final sub = ref.watch(connectivityChangesProvider).listen((_) => unawaited(reach.check()));
  ref.onDispose(sub.cancel);
  return reach;
});

final serverReachProvider = StreamProvider<ServerReach>((ref) async* {
  final reach = ref.watch(reachabilityProvider);
  yield reach.value;
  yield* reach.changes;
});

/// True only when the current server is known not to answer.
final isOfflineProvider = Provider<bool>((ref) => ref.watch(serverReachProvider).value == ServerReach.offline);

// --- Outbox ---

final outboxQueueProvider = Provider<OutboxQueue>((ref) => OutboxQueue(ref.watch(offlineDbProvider)));

final outboxFlusherProvider = Provider<OutboxFlusher>((ref) {
  return OutboxFlusher(
    db: ref.watch(offlineDbProvider),
    clientFor: (accountId) => accountClient(ref, accountId),
    onReachability: (accountId, reachable) {
      if (ref.read(currentAccountProvider).value?.id != accountId) return;
      final reach = ref.read(reachabilityProvider);
      reachable ? reach.reportSuccess() : reach.reportFailure();
    },
  );
});

/// Pending and failed changes, for the sync row.
final outboxCountsProvider = StreamProvider<OutboxCounts>((ref) => ref.watch(outboxQueueProvider).watchCounts());

/// Decides when the outbox flushes: when the server is back, every 5 min
/// in the foreground, on app foreground ([onForeground]), and shortly after
/// something was queued ([kick]).
class SyncScheduler {
  SyncScheduler(this._ref);
  final Ref _ref;
  Timer? _periodic;
  Timer? _debounce;
  StreamSubscription<ServerReach>? _sub;

  void start() {
    _sub ??= _ref.read(reachabilityProvider).changes.listen((reach) {
      if (reach == ServerReach.online) unawaited(flush());
    });
    _periodic ??= Timer.periodic(const Duration(minutes: 5), (_) => unawaited(flush()));
  }

  Future<void> flush() async {
    try {
      await _ref.read(outboxFlusherProvider).flush();
    } on Object catch (e) {
      debugPrint('Outbox flush stopped: $e');
    }
  }

  /// Something was queued: flush in a moment (several changes in a row go
  /// out together).
  void kick() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  Future<void> onForeground() async {
    await _ref.read(reachabilityProvider).check();
    await flush();
  }

  void dispose() {
    _periodic?.cancel();
    _debounce?.cancel();
    unawaited(_sub?.cancel());
  }
}

final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final scheduler = SyncScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Hooks that move a streamed book's listening offline when the network
/// goes (the Phase 3 handoff).
final offlineHooksProvider = Provider<OfflineHooks>((ref) {
  final db = ref.watch(offlineDbProvider);
  return OfflineHooks(
    recorder: (item, info) =>
        OfflineSessionRecorder(db: db, ref: item, info: info, onQueued: ref.read(syncSchedulerProvider).kick),
    queueFinished: (item, at) async {
      await OutboxQueue(db).enqueue(item, OutboxKind.markFinished, {'finishedAt': at.millisecondsSinceEpoch});
      ref.read(syncSchedulerProvider).kick();
    },
  );
});

// --- Downloads ---

final downloadTransportProvider = Provider<DownloadTransport>((ref) => BackgroundTransport());

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = AbsDownloadManager(
    db: ref.watch(offlineDbProvider),
    transport: ref.watch(downloadTransportProvider),
    supportDir: ref.watch(supportDirProvider),
    serverFor: (accountId) async => AbsDownloadServer(
      accountId: accountId,
      client: await accountClient(ref, accountId),
      store: ref.read(secureStoreProvider),
      refresher: ref.read(tokenRefresherProvider),
    ),
    excludeFromBackup: ref.read(deviceStorageProvider).excludeFromBackup,
    notificationTexts: (title) {
      final l10n = deviceL10n();
      return NotificationTexts(
        running: l10n.notificationDownloadRunning(title),
        progress: l10n.notificationDownloadFiles('{numFinished}', '{numTotal}'),
        complete: l10n.notificationDownloadComplete(title),
        failed: l10n.notificationDownloadFailed(title),
      );
    },
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Every download, keyed by `ItemRef.key`.
final downloadStatesProvider = StreamProvider<Map<String, DownloadState>>(
  (ref) => ref.watch(downloadManagerProvider).states,
);

/// The download state of one item ([DownloadPhase.none] when there is no
/// download).
final downloadStateProvider = Provider.family<DownloadState, ItemRef>(
  (ref, item) => ref.watch(downloadStatesProvider.select((v) => v.value?[item.key])) ?? DownloadState.none(item),
);

final downloadSettingsProvider = NotifierProvider<DownloadSettingsController, DownloadSettings>(
  DownloadSettingsController.new,
);

class DownloadSettingsController extends Notifier<DownloadSettings> {
  bool _loaded = false;

  @override
  DownloadSettings build() {
    unawaited(_load());
    return const DownloadSettings();
  }

  Future<void> _load() async {
    final saved = await DownloadSettings.load(ref.read(globalDbProvider));
    if (!_loaded) state = saved;
    _loaded = true;
  }

  Future<void> update(DownloadSettings Function(DownloadSettings) change) async {
    _loaded = true;
    final before = state;
    final next = change(state);
    state = next;
    await next.save(ref.read(globalDbProvider));
    if (before.wifiOnly != next.wifiOnly) await ref.read(downloadManagerProvider).setWifiOnly(next.wifiOnly);
    if (next.autoDeleteFinished || next.maxGigabytes > 0) await ref.read(downloadRulesProvider).run();
  }
}

/// Runs the automatic download rules (4.5).
class DownloadRulesRunner {
  DownloadRulesRunner(this._ref);
  final Ref _ref;
  final _nextAsked = <String>{};

  /// Storage rules: on app foreground and after each finished book.
  Future<void> run() async {
    final settings = await DownloadSettings.load(_ref.read(globalDbProvider));
    if (!settings.autoDeleteFinished && settings.maxGigabytes <= 0) return;
    final manager = _ref.read(downloadManagerProvider);
    final states = await manager.states.first;
    for (final key in downloadsToRemove(states.values, settings, DateTime.now())) {
      await manager.delete(key);
    }
  }

  /// Auto-download of the next book in a series past 75%.
  Future<void> onProgress(ItemRef item, double fraction) async {
    if (fraction < autoNextAt || item.episodeId != null || !_nextAsked.add(item.key)) return;
    final settings = _ref.read(downloadSettingsProvider);
    if (!settings.autoNextInSeries) return;
    final row = await _ref.read(offlineDbProvider).snapshot(item.key);
    if (row == null) return;
    try {
      final snap = ItemSnapshot.parse((jsonDecode(row.itemJson) as Map).cast<String, Object?>());
      final libraryId = snap.libraryId;
      if (snap.series.isEmpty || libraryId == null) return;
      await _ref
          .read(downloadManagerProvider)
          .enqueueSeries(
            item.source,
            libraryId: libraryId,
            seriesId: snap.series.first.id,
            after: item.itemId,
            limit: 1,
            reason: DownloadReason.series,
          );
    } on Object catch (e) {
      // Offline or the series is gone: try again next time the book plays.
      _nextAsked.remove(item.key);
      debugPrint('Downloads: next in series not queued: $e');
    }
  }
}

final downloadRulesProvider = Provider<DownloadRulesRunner>((ref) => DownloadRulesRunner(ref));

/// Offline playback of downloaded books.
final downloadedPlaybackProvider = Provider<DownloadedPlayback>((ref) {
  return DownloadedPlayback(
    db: ref.watch(offlineDbProvider),
    supportDir: ref.watch(supportDirProvider),
    deviceInfo: () async => (await PlaybackDevice.current(await ref.read(deviceIdProvider.future))).toJson(),
    directApi: (accountId) async {
      try {
        return _ClientProgressApi(await accountClient(ref, accountId));
      } on Object {
        return null;
      }
    },
    lastPosition: (item) async {
      final last = await ref.read(playerStoreProvider).loadLast();
      return last != null && last.ref == item ? PositionStamp(last.position, last.savedAt) : null;
    },
    isOnline: (accountId) =>
        ref.read(currentAccountProvider).value?.id != accountId || ref.read(reachabilityProvider).isOnline,
    onQueued: ref.read(syncSchedulerProvider).kick,
    onFinished: (item, at) async {
      await ref.read(downloadManagerProvider).markFinished(item.key, at);
      await ref.read(downloadRulesProvider).run();
    },
    onProgress: (item, fraction) => unawaited(ref.read(downloadRulesProvider).onProgress(item, fraction)),
  );
});

class _ClientProgressApi implements DirectProgressApi {
  _ClientProgressApi(this._client);
  final AbsClient _client;

  @override
  Future<void> patchProgress(ItemRef ref, Map<String, Object?> body) => _client.patch<Object?>(
    ref.episodeId == null ? '/api/me/progress/${ref.itemId}' : '/api/me/progress/${ref.itemId}/${ref.episodeId}',
    body: body,
  );

  @override
  void dispose() => _client.close();
}
