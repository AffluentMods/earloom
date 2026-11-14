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
  Uri url(String path) => _client.url(path);

  @override
  void dispose() => _client.close();
}

/// Opens server playback sessions and turns them into [PlayableBook]s.
final class AbsSessionStarter {
  AbsSessionStarter({required this.api, required this.device, this.localPosition});

  final AbsPlaybackApi api;
  final PlaybackDevice device;

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
    final parsed = parseSession(session, ref: ref, api: api);
    if (startAt != null) return (parsed.book, StartDecision(startAt));
    final local = await localPosition?.call(ref);
    final serverAt = parsed.progressUpdatedAt;
    final decision = resolveStart(
      local: local,
      server: PositionStamp(parsed.book.startPosition, serverAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return (parsed.book, decision);
  }

  /// Builds the book from a play response. Public for tests.
  static ({PlayableBook book, DateTime? progressUpdatedAt}) parseSession(
    Map<String, Object?> session, {
    required ItemRef ref,
    required AbsPlaybackApi api,
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
        Chapter(index: i, title: '${c['title'] ?? ''}', start: _seconds(c['start']), end: _seconds(c['end'])),
    ];
    final meta = (session['mediaMetadata'] as Map?)?.cast<String, Object?>() ?? const {};
    final item = (session['libraryItem'] as Map?)?.cast<String, Object?>() ?? const {};
    final updatedAt = (item['updatedAt'] as num?)?.toInt() ?? 0;
    final coverUrl = api.url('/api/items/${ref.itemId}/cover');
    final progress = (item['userMediaProgress'] as Map?)?.cast<String, Object?>();
    final lastUpdate = (progress?['lastUpdate'] as num?)?.toInt();
    final sink = AbsProgressSink(api: api, sessionId: id, itemId: ref.itemId, episodeId: ref.episodeId);
    return (
      book: PlayableBook(
        ref: ref,
        title: (session['displayTitle'] as String?) ?? (meta['title'] as String?) ?? '',
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

/// Reports to an open server session. Listening time that could not be
/// sent is kept and goes out with the next sync.
final class AbsProgressSink implements ProgressSink {
  AbsProgressSink({required this.api, required this.sessionId, required this.itemId, this.episodeId});

  final AbsPlaybackApi api;
  final String sessionId;
  final String itemId;
  final String? episodeId;
  Duration _unsent = Duration.zero;
  bool _closed = false;

  /// The server forgot the session (restart, another device of this user):
  /// further syncs are pointless. The engine reopens a session on the next
  /// stream failure.
  bool _gone = false;

  static double _secs(Duration d) => d.inMilliseconds / 1000;

  Map<String, Object?> _body(Duration position, Duration listened) => {
    'currentTime': _secs(position),
    'timeListened': _secs(listened),
  };

  @override
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying}) async {
    if (_closed || _gone) return;
    final listenedTotal = _unsent + listened;
    _unsent = listenedTotal;
    try {
      await api.sync(sessionId, _body(position, listenedTotal));
      _unsent = Duration.zero;
    } on AbsHttpError catch (e) {
      if (e.status == 404) _gone = true;
    } on AbsFailure {
      // Offline or the server is busy: keep the time for the next sync.
      // Phase 4 hands long gaps to the offline session outbox.
    }
  }

  @override
  Future<void> finished({required Duration position}) async {
    try {
      await api.markFinished(itemId, episodeId: episodeId);
    } on AbsFailure {
      // The sync at the very end already crossed the server's auto-finish
      // line in nearly every case.
    }
  }

  @override
  Future<void> close({required Duration position}) async {
    if (_closed) return;
    _closed = true;
    try {
      if (!_gone) await api.close(sessionId, _body(position, _unsent));
    } on AbsFailure {
      // The server closes idle sessions itself.
    } finally {
      api.dispose();
    }
  }
}
