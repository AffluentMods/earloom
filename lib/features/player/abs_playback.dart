// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/library/models.dart';
import '../../core/library/source_id.dart';
import '../../core/net/abs_client.dart';
import '../../core/net/abs_errors.dart';
import '../../core/ui/cover_image.dart';
import 'offline_session_recorder.dart';
import 'playable.dart';
import 'progress_resolver.dart';

/// Who is playing, as the server's device list and listening sessions show
/// it (docs/abs-api.md section 9).
final class PlaybackDevice {
  const PlaybackDevice({
    required this.deviceId,
    required this.clientVersion,
    this.manufacturer,
    this.model,
    this.osVersion,
  });

  final String deviceId;
  final String clientVersion;
  final String? manufacturer;
  final String? model;
  final String? osVersion;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'clientName': 'Earloom',
    'clientVersion': clientVersion,
    'manufacturer': ?manufacturer,
    'model': ?model,
    'sdkVersion': ?osVersion,
  };

  static Future<PlaybackDevice> current(String deviceId) async {
    final package = await PackageInfo.fromPlatform();
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return PlaybackDevice(
        deviceId: deviceId,
        clientVersion: package.version,
        manufacturer: a.manufacturer,
        model: a.model,
        osVersion: '${a.version.sdkInt}',
      );
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return PlaybackDevice(
        deviceId: deviceId,
        clientVersion: package.version,
        manufacturer: 'Apple',
        model: i.utsname.machine,
        osVersion: i.systemVersion,
      );
    }
    return PlaybackDevice(deviceId: deviceId, clientVersion: package.version);
  }
}

/// The audio types this phone plays itself. Anything else the server
/// transcodes to HLS. Without this list the server transcodes everything.
List<String> supportedMimeTypes() => [
  'audio/mpeg',
  'audio/mp4',
  'audio/x-m4a',
  'audio/x-m4b',
  'audio/aac',
  'audio/flac',
  'audio/x-flac',
  'audio/wav',
  'audio/x-wav',
  if (!Platform.isIOS) ...['audio/ogg', 'audio/opus', 'audio/webm', 'audio/x-matroska'],
];

/// What the player needs from a server: one client per account, made fresh
/// for each book so a book keeps playing when the user switches accounts.
abstract interface class AbsPlaybackApi {
  Future<Map<String, Object?>> openSession(String itemId, {String? episodeId, required Map<String, Object?> body});
  Future<void> sync(String sessionId, Map<String, Object?> body);
  Future<void> close(String sessionId, Map<String, Object?> body);
  Future<void> markFinished(String itemId, {String? episodeId});

  /// When the user's progress for the item last changed, or null if there
  /// is none.
  Future<DateTime?> progressUpdatedAt(String itemId, {String? episodeId});
  Uri url(String path);
  Map<String, String> get customHeaders;
  void dispose();
}

final class ClientPlaybackApi implements AbsPlaybackApi {
  ClientPlaybackApi(this._client, this.customHeaders);
  final AbsClient _client;

  @override
  final Map<String, String> customHeaders;

  @override
  Future<Map<String, Object?>> openSession(
    String itemId, {
    String? episodeId,
    required Map<String, Object?> body,
  }) async {
    final path = episodeId == null ? '/api/items/$itemId/play' : '/api/items/$itemId/play/$episodeId';
    final json = await _client.post<Map<String, Object?>>(path, body: body);
    return json;
  }

  @override
  Future<void> sync(String sessionId, Map<String, Object?> body) =>
      _client.post<Object?>('/api/session/$sessionId/sync', body: body);

  @override
  Future<void> close(String sessionId, Map<String, Object?> body) =>
      _client.post<Object?>('/api/session/$sessionId/close', body: body);

  @override
  Future<void> markFinished(String itemId, {String? episodeId}) => _client.patch<Object?>(
    episodeId == null ? '/api/me/progress/$itemId' : '/api/me/progress/$itemId/$episodeId',
    body: {'isFinished': true},
  );

  @override
  Future<DateTime?> progressUpdatedAt(String itemId, {String? episodeId}) async {
    try {
      final json = await _client.get<Map<String, Object?>>(
        episodeId == null ? '/api/me/progress/$itemId' : '/api/me/progress/$itemId/$episodeId',
      );
      final last = json['lastUpdate'];
      return last is num ? DateTime.fromMillisecondsSinceEpoch(last.toInt()) : null;
    } on AbsHttpError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Uri url(String path) => _client.url(path);

  @override
  void dispose() => _client.close();
}

/// Where a streamed book's listening goes when the server cannot be
/// reached (docs/plan/05-phase4-offline.md 4.6, the Phase 3 handoff).
final class OfflineHooks {
  const OfflineHooks({required this.recorder, required this.queueFinished});

  /// A recorder for this book's offline listening.
  final OfflineSessionRecorder Function(ItemRef ref, LocalSessionInfo info) recorder;

  /// Queues "finished" for when the server is back.
  final Future<void> Function(ItemRef ref, DateTime at) queueFinished;
}

/// Opens server playback sessions and turns them into [PlayableBook]s.
final class AbsSessionStarter {
  AbsSessionStarter({required this.api, required this.device, this.localPosition, this.offline});

  final AbsPlaybackApi api;
  final PlaybackDevice device;
  final OfflineHooks? offline;

  /// Where this phone last was in a book, for the "picked up on another
  /// device" check.
  final Future<PositionStamp?> Function(ItemRef ref)? localPosition;

  Future<(PlayableBook, StartDecision)> start(ItemRef ref, {Duration? startAt}) async {
    final session = await api.openSession(
      ref.itemId,
      episodeId: ref.episodeId,
      body: {
        'deviceInfo': device.toJson(),
        'forceDirectPlay': false,
        'forceTranscode': false,
        'supportedMimeTypes': supportedMimeTypes(),
        'mediaPlayer': 'earloom',
      },
    );
    final parsed = parseSession(session, ref: ref, api: api, offline: offline, deviceInfo: device.toJson());
    if (startAt != null) return (parsed.book, StartDecision(startAt));
    final local = await localPosition?.call(ref);
    DateTime? serverAt = parsed.progressUpdatedAt;
    if (local != null && serverAt == null) {
      try {
        serverAt = await api.progressUpdatedAt(ref.itemId, episodeId: ref.episodeId);
      } on AbsFailure {
        // Unknown: the server position stands.
      }
    }
    final decision = resolveStart(
      local: local,
      // With no timestamp at all, the server (what the session says) wins.
      server: PositionStamp(parsed.book.startPosition, serverAt ?? DateTime.now()),
    );
    return (parsed.book, decision);
  }

  /// Builds the book from a play response. Public for tests.
  static ({PlayableBook book, DateTime? progressUpdatedAt}) parseSession(
    Map<String, Object?> session, {
    required ItemRef ref,
    required AbsPlaybackApi api,
    OfflineHooks? offline,
    Map<String, Object?> deviceInfo = const {},
  }) {
    final id = session['id'];
    if (id is! String || id.isEmpty) throw const AbsUnexpected('Play session without an id');
    final transcode = session['playMethod'] == 2;
    final tracksJson = (session['audioTracks'] as List?) ?? const [];
    if (tracksJson.isEmpty) throw const AbsUnexpected('Play session without audio tracks');
    final headers = api.customHeaders;
    final tracks = <PlayableTrack>[];
    for (final raw in tracksJson.cast<Map<String, Object?>>()) {
      final index = (raw['index'] as num?)?.toInt() ?? tracks.length + 1;
      final contentUrl = raw['contentUrl'] as String? ?? '';
      final uri = transcode
          // The HLS playlist needs no auth: the session id is the key.
          ? api.url(contentUrl)
          // The public session route needs no token and honors Range, so a
          // long book never stalls on an expired token.
          : api.url('/public/session/$id/track/$index');
      tracks.add(
        PlayableTrack(
          uri: uri,
          start: _seconds(raw['startOffset']),
          duration: _seconds(raw['duration']),
          headers: headers,
          mimeType: raw['mimeType'] as String?,
        ),
      );
    }
    final chapters = [
      for (final (i, c) in ((session['chapters'] as List?) ?? const []).cast<Map<String, Object?>>().indexed)
        Chapter(index: i, title: (c['title'] ?? '').toString(), start: _seconds(c['start']), end: _seconds(c['end'])),
    ];
    final meta = (session['mediaMetadata'] as Map?)?.cast<String, Object?>() ?? const {};
    final item = (session['libraryItem'] as Map?)?.cast<String, Object?>() ?? const {};
    final updatedAt = (item['updatedAt'] as num?)?.toInt() ?? 0;
    final coverUrl = api.url('/api/items/${ref.itemId}/cover');
    final progress = (item['userMediaProgress'] as Map?)?.cast<String, Object?>();
    final lastUpdate = (progress?['lastUpdate'] as num?)?.toInt();
    final title = (session['displayTitle'] as String?) ?? (meta['title'] as String?) ?? '';
    final info = LocalSessionInfo(
      duration: _seconds(session['duration']),
      deviceInfo: deviceInfo,
      libraryId: session['libraryId'] as String?,
      mediaType: (session['mediaType'] as String?) ?? (ref.episodeId == null ? 'book' : 'podcast'),
      displayTitle: title,
      displayAuthor: _nonEmpty(session['displayAuthor'] as String?),
      mediaMetadata: {
        'title': ?(meta['title'] as String?),
        'authorName': ?(meta['authorName'] as String?),
        'narratorName': ?(meta['narratorName'] as String?),
        'seriesName': ?(meta['seriesName'] as String?),
      },
    );
    final sink = AbsProgressSink(
      api: api,
      sessionId: id,
      itemId: ref.itemId,
      episodeId: ref.episodeId,
      recorder: offline == null ? null : () => offline.recorder(ref, info),
      queueFinished: offline == null ? null : (at) => offline.queueFinished(ref, at),
      startPosition: _seconds(session['currentTime']),
    );
    return (
      book: PlayableBook(
        ref: ref,
        title: title,
        author: _nonEmpty(session['displayAuthor'] as String?),
        narrator: _nonEmpty(meta['narratorName'] as String?),
        seriesLine: _nonEmpty(meta['seriesName'] as String?),
        tracks: tracks,
        chapters: chapters,
        startPosition: _seconds(session['currentTime']),
        artworkUri: coverUrl.replace(queryParameters: {'width': '512', 'format': 'jpeg'}),
        cover: NetworkCover(itemCoverUrl: coverUrl, cacheKey: '${ref.itemId}-$updatedAt', headers: headers),
        coverKey: '${ref.itemId}-$updatedAt',
        sink: sink,
      ),
      progressUpdatedAt: lastUpdate == null ? null : DateTime.fromMillisecondsSinceEpoch(lastUpdate),
    );
  }

  static Duration _seconds(Object? value) =>
      value is num ? Duration(milliseconds: (value * 1000).round()) : Duration.zero;

  static String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s;
}

/// Reports to an open server session.
///
/// When a sync fails because the server cannot be reached (or forgot the
/// session), the listening moves to a local session from that moment: the
/// time the server never got goes into it, and every later report too,
/// until a sync gets through again. Then the local session is closed and
/// queued for `/api/session/local-all`. Each second of listening is counted
/// exactly once: either it went out in a sync, or it is in the local session.
final class AbsProgressSink implements ProgressSink {
  AbsProgressSink({
    required this.api,
    required this.sessionId,
    required this.itemId,
    this.episodeId,
    OfflineSessionRecorder Function()? recorder,
    this._queueFinished,
    Duration startPosition = Duration.zero,
    DateTime Function()? clock,
  }) : _recorderFactory = recorder,
       _lastSynced = startPosition,
       _clock = clock ?? DateTime.now {
    _own.add(sessionId);
  }

  /// Sessions this phone opened. Their progress events come back over the
  /// socket and must not be mistaken for another device.
  static final _own = <String>{};
  static bool isOwnSession(String id) => _own.contains(id);

  final AbsPlaybackApi api;
  final String sessionId;
  final String itemId;
  final String? episodeId;
  final OfflineSessionRecorder Function()? _recorderFactory;
  final Future<void> Function(DateTime at)? _queueFinished;
  final DateTime Function() _clock;
  Duration _unsent = Duration.zero;
  Duration _lastSynced;
  bool _closed = false;

  /// The server forgot the session (restart, another device of this user):
  /// further syncs are pointless. The engine reopens a session on the next
  /// stream failure.
  bool _gone = false;
  OfflineSessionRecorder? _recorder;

  /// True while listening goes to the local session.
  bool get isOffline => _recorder?.isOpen ?? false;

  static double _secs(Duration d) => d.inMilliseconds / 1000;

  Map<String, Object?> _body(Duration position, Duration listened) => {
    'currentTime': _secs(position),
    'timeListened': _secs(listened),
  };

  @override
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying}) async {
    if (_closed) return;
    if (isOffline) {
      await _recorder!.record(position: position, listened: listened);
      if (!_gone) await _probe(position);
      return;
    }
    final listenedTotal = _unsent + listened;
    _unsent = listenedTotal;
    if (_gone) {
      await _handOff(position);
      return;
    }
    try {
      await api.sync(sessionId, _body(position, listenedTotal));
      _unsent = Duration.zero;
      _lastSynced = position;
    } on AbsHttpError catch (e) {
      if (e.status == 404) {
        _gone = true;
        await _handOff(position);
      }
    } on AbsUnreachable {
      await _handOff(position);
    } on AbsFailure {
      // The server answered but is busy (5xx, 429): keep the time for the
      // next sync.
    }
  }

  /// Moves the unsent time into a new local session. Without a recorder
  /// (tests, no offline database) the time stays in memory as before.
  Future<void> _handOff(Duration position) async {
    final factory = _recorderFactory;
    if (factory == null) return;
    final recorder = _recorder ??= factory();
    await recorder.record(position: position, listened: _unsent, startAt: _lastSynced);
    _unsent = Duration.zero;
  }

  /// While offline: a sync with no listening time tells whether the server
  /// is back (and moves progress there). If it is, the local session ends.
  Future<void> _probe(Duration position) async {
    try {
      await api.sync(sessionId, _body(position, Duration.zero));
    } on AbsHttpError catch (e) {
      if (e.status == 404) _gone = true;
      return;
    } on AbsFailure {
      return;
    }
    _lastSynced = position;
    await _recorder!.close(position: position);
  }

  @override
  Future<void> finished({required Duration position}) async {
    try {
      await api.markFinished(itemId, episodeId: episodeId);
    } on AbsFailure {
      // Usually the sync at the very end already crossed the server's
      // auto-finish line; queue it anyway so an offline finish is never lost.
      await _queueFinished?.call(_clock());
    }
  }

  @override
  Future<void> close({required Duration position}) async {
    if (_closed) return;
    _closed = true;
    try {
      if (isOffline) {
        await _recorder!.close(position: position);
        if (!_gone) await api.close(sessionId, _body(position, Duration.zero));
      } else if (!_gone) {
        await api.close(sessionId, _body(position, _unsent));
        _unsent = Duration.zero;
      }
    } on AbsUnreachable {
      // The last bit of listening must not be lost: record it locally.
      if (_unsent > Duration.zero && _recorderFactory != null) {
        await _handOff(position);
        await _recorder?.close(position: position);
      }
    } on AbsFailure {
      // The server closes idle sessions itself.
    } finally {
      api.dispose();
    }
  }
}
