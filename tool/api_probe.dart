// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Re-checks the Audiobookshelf endpoints Earloom depends on. Run it against the
// local dev server after every ABS upgrade, then compare with docs/abs-api.md.
//
//   cd tool/abs-dev && docker compose up -d
//   dart run tool/api_probe.dart                 (from the repo root)
//   dart run tool/api_probe.dart --url=http://localhost:13378
//
// It logs in as `affluent` with the password from tool/abs-dev/.env.local
// (never printed), calls each endpoint and prints one line per check:
//   OK    <check>
//   FAIL  <check>: <what differed>
// The exit code is 1 when any check fails, 2 when the script cannot start.
//
// Side effects on the server, kept as small as possible:
//   - Opens and closes three playback sessions with no listening time, so no
//     listening session is stored and stats do not change.
//   - Syncs one book at its current position (only its lastUpdate changes).
//   - Creates and deletes one bookmark.
//   - Uses 5 of the 40 auth requests ABS allows per IP in 10 minutes.
// Uses only dart:io and dart:convert, so it needs no packages.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final base = args
      .firstWhere((a) => a.startsWith('--url='), orElse: () => '--url=http://localhost:13378')
      .substring('--url='.length)
      .replaceAll(RegExp(r'/+$'), '');
  final envFile = File('${File.fromUri(Platform.script).parent.path}/abs-dev/.env.local');
  final password = _readEnv(envFile, 'ABS_AFFLUENT_PASSWORD');
  if (password == null) {
    stderr.writeln('Could not read ABS_AFFLUENT_PASSWORD from ${envFile.path}.');
    stderr.writeln('Run "dart run tool/abs-dev/setup.dart" first.');
    exit(2);
  }

  final probe = _Probe(base);
  stdout.writeln('Probing $base');
  await probe.run(password);
  probe.close();

  stdout.writeln('');
  stdout.writeln('${probe.passed} passed, ${probe.failed} failed.');
  exit(probe.failed == 0 ? 0 : 1);
}

String? _readEnv(File file, String key) {
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('$key=')) return line.substring(key.length + 1).trim();
  }
  return null;
}

class _Res {
  _Res(this.status, this.headers, this.bytes);

  final int status;
  final HttpHeaders headers;
  final List<int> bytes;

  String get text => utf8.decode(bytes, allowMalformed: true);

  Object? get json {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  String header(String name) => headers.value(name) ?? '';
}

class _Probe {
  _Probe(this.base) : _http = HttpClient() {
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  final String base;
  final HttpClient _http;
  int passed = 0;
  int failed = 0;
  String? _note;

  static const _deviceInfo = {
    'deviceId': 'earloom-api-probe',
    'clientName': 'Earloom API probe',
    'clientVersion': '0.0.0',
    'manufacturer': 'Affluent Labs',
    'model': 'api_probe',
  };

  void close() => _http.close(force: true);

  Future<_Res> send(
    String method,
    String path, {
    String? bearer,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final req = await _http.openUrl(method, Uri.parse('$base$path'));
    req.followRedirects = false;
    if (bearer != null) req.headers.set('Authorization', 'Bearer $bearer');
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
    }
    return _Res(res.statusCode, res.headers, bytes);
  }

  /// Runs one check. The body returns null when all is well, or what differed.
  Future<bool> check(String name, Future<String?> Function() body) async {
    _note = null;
    String? problem;
    try {
      problem = await body();
    } on TimeoutException {
      problem = 'timed out';
    } on SocketException catch (e) {
      problem = 'connection failed (${e.osError?.message ?? e.message})';
    } on HttpException catch (e) {
      problem = 'HTTP error (${e.message})';
    } on TypeError {
      problem = 'response had an unexpected shape';
    } on StateError catch (e) {
      problem = e.message;
    }
    if (problem == null) {
      passed++;
      stdout.writeln('OK    $name${_note == null ? '' : '  ($_note)'}');
      return true;
    }
    failed++;
    stdout.writeln('FAIL  $name: $problem');
    return false;
  }

  /// Returns the dotted paths that are absent. `[]` steps into the first list entry.
  static String? missing(Object? root, List<String> paths) {
    final absent = <String>[];
    for (final path in paths) {
      Object? node = root;
      var found = true;
      for (final rawPart in path.split('.')) {
        final isList = rawPart.endsWith('[]');
        final part = isList ? rawPart.substring(0, rawPart.length - 2) : rawPart;
        if (part.isNotEmpty) {
          if (node is Map && node.containsKey(part)) {
            node = node[part];
          } else {
            found = false;
            break;
          }
        }
        if (isList) {
          if (node is List && node.isNotEmpty) {
            node = node.first;
          } else {
            found = false;
            break;
          }
        }
      }
      if (!found) absent.add(path);
    }
    return absent.isEmpty ? null : 'missing ${absent.join(', ')}';
  }

  static String? expectStatus(_Res res, int status) =>
      res.status == status ? null : 'expected HTTP $status, got ${res.status}';

  static Map<String, dynamic>? jwtClaims(Object? token) {
    if (token is! String) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> run(String password) async {
    // ---- Reachability -----------------------------------------------------
    await check('GET /ping', () async {
      final res = await send('GET', '/ping');
      return expectStatus(res, 200) ?? missing(res.json, ['success']);
    });

    await check('GET /status', () async {
      final res = await send('GET', '/status');
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, ['app', 'serverVersion', 'isInit', 'authMethods', 'authFormData']);
      if (problem != null) return problem;
      final json = res.json as Map<String, dynamic>;
      if (json['app'] != 'audiobookshelf') return 'app is not "audiobookshelf"';
      if (json['authMethods'] is! List) return 'authMethods is not a list';
      if (json['authFormData'] is! Map) return 'authFormData is not an object';
      _note = 'server ${json['serverVersion']}, auth ${(json['authMethods'] as List).join('+')}';
      return null;
    });

    // ---- Login ------------------------------------------------------------
    String? access;
    String? refresh;
    final loggedIn = await check('POST /login with x-return-tokens', () async {
      final res = await send(
        'POST',
        '/login',
        headers: {'x-return-tokens': 'true'},
        body: {'username': 'affluent', 'password': password},
      );
      if (res.status == 429) return 'rate limited (HTTP 429), wait up to 10 minutes';
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, [
            'user.id',
            'user.username',
            'user.type',
            'user.accessToken',
            'user.refreshToken',
            'user.permissions.download',
            'user.permissions.update',
            'user.permissions.delete',
            'user.permissions.upload',
            'user.mediaProgress',
            'user.bookmarks',
            'userDefaultLibraryId',
            'serverSettings.version',
          ]);
      if (problem != null) return problem;
      final user = (res.json as Map<String, dynamic>)['user'] as Map<String, dynamic>;
      final accessClaims = jwtClaims(user['accessToken']);
      final refreshClaims = jwtClaims(user['refreshToken']);
      if (accessClaims == null || refreshClaims == null) return 'tokens are not JWTs';
      if (accessClaims['type'] != 'access') return 'access token claim "type" is not "access"';
      if (refreshClaims['type'] != 'refresh') return 'refresh token claim "type" is not "refresh"';
      if (accessClaims['exp'] is! int || accessClaims['iat'] is! int) return 'access token has no exp or iat';
      access = user['accessToken'] as String;
      refresh = user['refreshToken'] as String;
      final lifetime = (accessClaims['exp'] as int) - (accessClaims['iat'] as int);
      _note = 'access token lifetime ${lifetime}s, legacy user.token ${user['token'] == null ? 'absent' : 'present'}';
      return null;
    });
    if (!loggedIn) {
      stdout.writeln('Login failed, skipping the remaining checks.');
      return;
    }

    await check('POST /login wrong password is 401', () async {
      final res = await send('POST', '/login', body: {'username': 'affluent', 'password': 'not-the-password'});
      return expectStatus(res, 401);
    });

    await check('GET /api/me without or with a bad token is 401', () async {
      final none = await send('GET', '/api/me');
      final bad = await send('GET', '/api/me', bearer: 'not-a-token');
      return expectStatus(none, 401) ?? expectStatus(bad, 401);
    });

    await check('refresh token is rejected as a Bearer token (CVE-2026-73085)', () async {
      final res = await send('GET', '/api/me', bearer: refresh);
      return res.status == 401 ? null : 'expected HTTP 401, got ${res.status}: update the server';
    });

    // ---- Refresh ----------------------------------------------------------
    final oldRefresh = refresh;
    await check('POST /auth/refresh rotates the refresh token', () async {
      final res = await send('POST', '/auth/refresh', headers: {'x-refresh-token': refresh!});
      final problem = expectStatus(res, 200) ?? missing(res.json, ['user.accessToken', 'user.refreshToken']);
      if (problem != null) return problem;
      final user = (res.json as Map<String, dynamic>)['user'] as Map<String, dynamic>;
      if (user['refreshToken'] == refresh) return 'refresh token was not rotated';
      if (user['accessToken'] == access) return 'access token was not replaced';
      access = user['accessToken'] as String;
      refresh = user['refreshToken'] as String;
      return null;
    });

    await check('POST /auth/refresh with the previous refresh token', () async {
      final res = await send('POST', '/auth/refresh', headers: {'x-refresh-token': oldRefresh!});
      if (res.status == 401) {
        _note = 'rejected with 401: no grace period on this server';
        return null;
      }
      final problem = expectStatus(res, 200) ?? missing(res.json, ['user.accessToken', 'user.refreshToken']);
      if (problem != null) return problem;
      final user = (res.json as Map<String, dynamic>)['user'] as Map<String, dynamic>;
      if (user['refreshToken'] != refresh) return 'grace reply did not return the current refresh token';
      access = user['accessToken'] as String;
      _note = 'grace period: got the already rotated token back';
      return null;
    });

    await check('POST /auth/refresh without a token is 401', () async {
      final res = await send('POST', '/auth/refresh');
      return expectStatus(res, 401) ?? missing(res.json, ['error']);
    });

    // ---- Me ---------------------------------------------------------------
    await check('POST /api/authorize', () async {
      final res = await send('POST', '/api/authorize', bearer: access);
      return expectStatus(res, 200) ??
          missing(res.json, ['user.id', 'user.type', 'user.permissions', 'userDefaultLibraryId', 'serverSettings']);
    });

    await check('GET /api/me', () async {
      final res = await send('GET', '/api/me', bearer: access);
      return expectStatus(res, 200) ??
          missing(res.json, ['id', 'username', 'type', 'permissions.download', 'mediaProgress', 'bookmarks']);
    });

    await check('GET /api/me/items-in-progress', () async {
      final res = await send('GET', '/api/me/items-in-progress', bearer: access);
      return expectStatus(res, 200) ?? missing(res.json, ['libraryItems']);
    });

    // ---- Libraries --------------------------------------------------------
    String? bookLibrary;
    String? podcastLibrary;
    await check('GET /api/libraries', () async {
      final res = await send('GET', '/api/libraries', bearer: access);
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, [
            'libraries[].id',
            'libraries[].name',
            'libraries[].mediaType',
            'libraries[].displayOrder',
          ]);
      if (problem != null) return problem;
      for (final lib in ((res.json as Map<String, dynamic>)['libraries'] as List).cast<Map<String, dynamic>>()) {
        if (lib['mediaType'] == 'book') bookLibrary ??= lib['id'] as String;
        if (lib['mediaType'] == 'podcast') podcastLibrary ??= lib['id'] as String;
      }
      return bookLibrary == null ? 'no book library on the server' : null;
    });
    if (bookLibrary == null) return;

    String? bookId;
    await check('GET /api/libraries/:id/items (paged, minified)', () async {
      final res = await send(
        'GET',
        '/api/libraries/$bookLibrary/items?limit=20&page=0&minified=1&sort=media.metadata.title',
        bearer: access,
      );
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, [
            'total',
            'limit',
            'page',
            'results[].id',
            'results[].mediaType',
            'results[].addedAt',
            'results[].updatedAt',
            'results[].media.metadata.title',
            'results[].media.metadata.authorName',
            'results[].media.duration',
            'results[].media.numTracks',
          ]);
      if (problem != null) return problem;
      // Prefer a multi-file book so several tracks get exercised.
      var mostTracks = -1;
      for (final item in ((res.json as Map<String, dynamic>)['results'] as List).cast<Map<String, dynamic>>()) {
        final tracks = ((item['media'] as Map<String, dynamic>)['numTracks'] as num).toInt();
        if (tracks > mostTracks) {
          mostTracks = tracks;
          bookId = item['id'] as String;
        }
      }
      return null;
    });
    if (bookId == null) return;

    await check('GET /api/libraries/:id/personalized', () async {
      final res = await send('GET', '/api/libraries/$bookLibrary/personalized?limit=5', bearer: access);
      if (res.status != 200) return expectStatus(res, 200);
      final shelves = res.json;
      if (shelves is! List) return 'response is not a list of shelves';
      if (shelves.isEmpty) {
        _note = 'no shelves yet';
        return null;
      }
      return missing(
        {'s': shelves},
        ['s[].id', 's[].label', 's[].labelStringKey', 's[].type', 's[].entities', 's[].total'],
      );
    });

    for (final entry in {
      'series': 'results',
      'collections': 'results',
      'playlists': 'results',
      'authors': 'authors',
    }.entries) {
      await check('GET /api/libraries/:id/${entry.key}', () async {
        final res = await send('GET', '/api/libraries/$bookLibrary/${entry.key}', bearer: access);
        return expectStatus(res, 200) ?? missing(res.json, [entry.value]);
      });
    }

    await check('GET /api/libraries/:id/filterdata', () async {
      final res = await send('GET', '/api/libraries/$bookLibrary/filterdata', bearer: access);
      return expectStatus(res, 200) ??
          missing(res.json, ['authors', 'genres', 'tags', 'series', 'narrators', 'languages', 'publishers']);
    });

    await check('GET /api/libraries/:id/search', () async {
      final res = await send('GET', '/api/libraries/$bookLibrary/search?q=the&limit=3', bearer: access);
      return expectStatus(res, 200) ?? missing(res.json, ['book', 'authors', 'series', 'narrators', 'tags', 'genres']);
    });

    // ---- Item and cover ---------------------------------------------------
    var mimeTypes = <String>['audio/mpeg', 'audio/mp4'];
    String? firstIno;
    await check('GET /api/items/:id?expanded=1&include=progress', () async {
      final res = await send('GET', '/api/items/$bookId?expanded=1&include=progress', bearer: access);
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, [
            'id',
            'libraryId',
            'mediaType',
            'updatedAt',
            'libraryFiles',
            'media.metadata.title',
            'media.metadata.authors',
            'media.metadata.narrators',
            'media.metadata.series',
            'media.metadata.description',
            'media.coverPath',
            'media.duration',
            'media.chapters',
            'media.audioFiles[].ino',
            'media.audioFiles[].mimeType',
            'media.audioFiles[].duration',
            'media.audioFiles[].metadata.size',
            'media.tracks[].contentUrl',
            'media.tracks[].startOffset',
          ]);
      if (problem != null) return problem;
      final files = (((res.json as Map<String, dynamic>)['media'] as Map<String, dynamic>)['audioFiles'] as List)
          .cast<Map<String, dynamic>>();
      mimeTypes = files.map((f) => f['mimeType'] as String).toSet().toList();
      firstIno = files.first['ino'] as String;
      return null;
    });

    await check('GET /api/items/:id/cover needs no auth, honors width and format', () async {
      final webp = await send('GET', '/api/items/$bookId/cover?width=64&format=webp');
      final jpeg = await send('GET', '/api/items/$bookId/cover?width=64&format=jpeg');
      final raw = await send('GET', '/api/items/$bookId/cover?raw=1');
      if (webp.status != 200) return 'webp: expected HTTP 200 without auth, got ${webp.status}';
      if (!webp.header('content-type').startsWith('image/webp')) {
        return 'webp: content type ${webp.header('content-type')}';
      }
      if (jpeg.status != 200 || !jpeg.header('content-type').startsWith('image/jpeg')) {
        return 'jpeg: HTTP ${jpeg.status}, content type ${jpeg.header('content-type')}';
      }
      if (raw.status != 200 || !raw.header('content-type').startsWith('image/')) {
        return 'raw: HTTP ${raw.status}, content type ${raw.header('content-type')}';
      }
      return null;
    });

    // ---- Play session -----------------------------------------------------
    String? sessionId;
    String? contentUrl;
    int? trackIndex;
    num? currentTime;
    num? duration;
    await check('POST /api/items/:id/play (direct play)', () async {
      final res = await send(
        'POST',
        '/api/items/$bookId/play',
        bearer: access,
        body: {
          'deviceInfo': _deviceInfo,
          'forceDirectPlay': false,
          'forceTranscode': false,
          'supportedMimeTypes': mimeTypes,
          'mediaPlayer': 'earloom-probe',
        },
      );
      final problem =
          expectStatus(res, 200) ??
          missing(res.json, [
            'id',
            'libraryItemId',
            'mediaType',
            'duration',
            'currentTime',
            'startTime',
            'playMethod',
            'chapters',
            'displayTitle',
            'displayAuthor',
            'audioTracks[].index',
            'audioTracks[].contentUrl',
            'audioTracks[].startOffset',
            'audioTracks[].duration',
            'audioTracks[].mimeType',
          ]);
      if (problem != null) return problem;
      final json = res.json as Map<String, dynamic>;
      if (json['playMethod'] != 0) return 'playMethod is ${json['playMethod']}, expected 0 (direct play)';
      final track = (json['audioTracks'] as List).first as Map<String, dynamic>;
      sessionId = json['id'] as String;
      contentUrl = track['contentUrl'] as String;
      trackIndex = (track['index'] as num).toInt();
      currentTime = json['currentTime'] as num;
      duration = json['duration'] as num;
      if (!contentUrl!.startsWith('/api/items/')) return 'contentUrl no longer starts with /api/items/';
      _note = '${(json['audioTracks'] as List).length} tracks';
      return null;
    });

    if (sessionId != null) {
      await check('GET /public/session/:id/track/:index streams without auth, honors Range', () async {
        final res = await send(
          'GET',
          '/public/session/$sessionId/track/$trackIndex',
          headers: {'Range': 'bytes=1000-1999'},
        );
        if (res.status != 206) return 'expected HTTP 206, got ${res.status}';
        if (!res.header('content-range').startsWith('bytes 1000-1999/')) {
          return 'Content-Range is "${res.header('content-range')}"';
        }
        return res.bytes.length == 1000 ? null : 'got ${res.bytes.length} bytes, expected 1000';
      });

      await check('contentUrl needs a Bearer token, honors Range', () async {
        final anonymous = await send('GET', contentUrl!, headers: {'Range': 'bytes=0-99'});
        final authed = await send('GET', contentUrl!, bearer: access, headers: {'Range': 'bytes=0-99'});
        if (anonymous.status != 401) return 'without a token: expected HTTP 401, got ${anonymous.status}';
        if (authed.status != 206) return 'with a token: expected HTTP 206, got ${authed.status}';
        return null;
      });

      await check('GET /api/items/:id/file/:ino/download honors Range', () async {
        final res = await send(
          'GET',
          '/api/items/$bookId/file/$firstIno/download',
          bearer: access,
          headers: {'Range': 'bytes=0-99'},
        );
        if (res.status != 206) return 'expected HTTP 206, got ${res.status}';
        if (!res.header('content-disposition').startsWith('attachment')) return 'no attachment Content-Disposition';
        return null;
      });

      await check('POST /api/session/:id/sync', () async {
        final res = await send(
          'POST',
          '/api/session/$sessionId/sync',
          bearer: access,
          body: {'currentTime': currentTime, 'timeListened': 0, 'duration': duration},
        );
        return expectStatus(res, 200);
      });

      await check('GET /api/me/progress/:itemId', () async {
        final res = await send('GET', '/api/me/progress/$bookId', bearer: access);
        return expectStatus(res, 200) ??
            missing(res.json, [
              'id',
              'libraryItemId',
              'episodeId',
              'duration',
              'progress',
              'currentTime',
              'isFinished',
              'lastUpdate',
              'startedAt',
              'finishedAt',
            ]);
      });

      await check('POST /api/session/:id/close, then the session is gone', () async {
        final close = await send('POST', '/api/session/$sessionId/close', bearer: access);
        if (close.status != 200) return 'close: expected HTTP 200, got ${close.status}';
        final sync = await send(
          'POST',
          '/api/session/$sessionId/sync',
          bearer: access,
          body: {'currentTime': currentTime, 'timeListened': 0},
        );
        if (sync.status != 404) return 'sync after close: expected HTTP 404, got ${sync.status}';
        final track = await send(
          'GET',
          '/public/session/$sessionId/track/$trackIndex',
          headers: {'Range': 'bytes=0-9'},
        );
        return track.status == 404 ? null : 'public track after close: expected HTTP 404, got ${track.status}';
      });
    }

    await check('POST /api/items/:id/play with forceTranscode returns HLS', () async {
      final res = await send(
        'POST',
        '/api/items/$bookId/play',
        bearer: access,
        body: {
          'deviceInfo': _deviceInfo,
          'forceTranscode': true,
          'supportedMimeTypes': mimeTypes,
          'mediaPlayer': 'earloom-probe',
        },
      );
      final problem = expectStatus(res, 200) ?? missing(res.json, ['id', 'playMethod', 'audioTracks[].contentUrl']);
      if (problem != null) return problem;
      final json = res.json as Map<String, dynamic>;
      final id = json['id'] as String;
      final url = ((json['audioTracks'] as List).first as Map<String, dynamic>)['contentUrl'] as String;
      String? result;
      if (json['playMethod'] != 2) {
        result = 'playMethod is ${json['playMethod']}, expected 2 (transcode)';
      } else if (url != '/hls/$id/output.m3u8') {
        result = 'HLS contentUrl shape changed';
      } else {
        final playlist = await send('GET', url);
        if (playlist.status != 200 || !playlist.text.startsWith('#EXTM3U')) {
          result = 'playlist without auth: HTTP ${playlist.status}';
        }
      }
      await send('POST', '/api/session/$id/close', bearer: access);
      return result;
    });

    // ---- Bookmarks --------------------------------------------------------
    await check('bookmark create and delete', () async {
      const time = 0.125;
      final create = await send(
        'POST',
        '/api/me/item/$bookId/bookmark',
        bearer: access,
        body: {'time': time, 'title': 'api_probe temporary bookmark'},
      );
      final problem =
          expectStatus(create, 200) ?? missing(create.json, ['libraryItemId', 'time', 'title', 'createdAt']);
      final delete = await send('DELETE', '/api/me/item/$bookId/bookmark/$time', bearer: access);
      if (problem != null) return 'create: $problem';
      return delete.status == 200 ? null : 'delete: expected HTTP 200, got ${delete.status}';
    });

    // ---- Stats and local sessions ------------------------------------------
    await check('GET /api/me/listening-stats', () async {
      final res = await send('GET', '/api/me/listening-stats', bearer: access);
      return expectStatus(res, 200) ??
          missing(res.json, ['totalTime', 'items', 'days', 'dayOfWeek', 'today', 'recentSessions']);
    });

    await check('GET /api/me/listening-sessions', () async {
      final res = await send('GET', '/api/me/listening-sessions?itemsPerPage=5&page=0', bearer: access);
      return expectStatus(res, 200) ?? missing(res.json, ['total', 'numPages', 'page', 'itemsPerPage', 'sessions']);
    });

    await check('POST /api/session/local-all (empty batch)', () async {
      final res = await send(
        'POST',
        '/api/session/local-all',
        bearer: access,
        body: {'deviceInfo': _deviceInfo, 'sessions': <Object>[]},
      );
      return expectStatus(res, 200) ?? missing(res.json, ['results']);
    });

    // ---- Podcasts ---------------------------------------------------------
    if (podcastLibrary != null) {
      await check('podcast item, recent episodes and episode play', () async {
        final items = await send(
          'GET',
          '/api/libraries/$podcastLibrary/items?limit=1&page=0&minified=1',
          bearer: access,
        );
        var problem = expectStatus(items, 200) ?? missing(items.json, ['results[].id', 'results[].media.numEpisodes']);
        if (problem != null) return 'items: $problem';
        final podcastId =
            (((items.json as Map<String, dynamic>)['results'] as List).first as Map<String, dynamic>)['id'];

        final recent = await send(
          'GET',
          '/api/libraries/$podcastLibrary/recent-episodes?limit=5&page=0',
          bearer: access,
        );
        problem = expectStatus(recent, 200) ?? missing(recent.json, ['episodes']);
        if (problem != null) return 'recent-episodes: $problem';

        final item = await send('GET', '/api/items/$podcastId?expanded=1&include=progress', bearer: access);
        problem =
            expectStatus(item, 200) ??
            missing(item.json, [
              'media.metadata.title',
              'media.episodes[].id',
              'media.episodes[].title',
              'media.episodes[].audioFile.mimeType',
              'media.episodes[].audioFile.ino',
            ]);
        if (problem != null) return 'item: $problem';
        final episode =
            ((((item.json as Map<String, dynamic>)['media'] as Map<String, dynamic>)['episodes'] as List).first
                as Map<String, dynamic>);
        final mime = (episode['audioFile'] as Map<String, dynamic>)['mimeType'];

        final play = await send(
          'POST',
          '/api/items/$podcastId/play/${episode['id']}',
          bearer: access,
          body: {
            'deviceInfo': _deviceInfo,
            'supportedMimeTypes': [mime],
            'mediaPlayer': 'earloom-probe',
          },
        );
        problem = expectStatus(play, 200) ?? missing(play.json, ['id', 'episodeId', 'audioTracks[].contentUrl']);
        if (play.status == 200) {
          await send('POST', '/api/session/${(play.json as Map<String, dynamic>)['id']}/close', bearer: access);
        }
        if (problem != null) return 'play: $problem';
        final json = play.json as Map<String, dynamic>;
        if (json['episodeId'] != episode['id']) return 'play: episodeId does not match';
        return json['playMethod'] == 0 ? null : 'play: playMethod is ${json['playMethod']}, expected 0';
      });
    }

    // ---- Socket -----------------------------------------------------------
    await check('socket.io: "auth" event with the access token answers "init"', () async {
      final event = await _socketAuth(access!);
      if (event == null) return 'no reply within 10 seconds';
      if (event.name != 'init') return 'got "${event.name}" instead of "init"';
      return missing(event.payload, ['userId', 'username']);
    });

    await check('socket.io: "auth" with a bad token answers "auth_failed"', () async {
      final event = await _socketAuth('not-a-token');
      if (event == null) return 'no reply within 10 seconds';
      if (event.name != 'auth_failed') return 'got "${event.name}" instead of "auth_failed"';
      return missing(event.payload, ['message']);
    });

    // ---- Logout -----------------------------------------------------------
    await check('POST /logout revokes the refresh token', () async {
      final res = await send('POST', '/logout', headers: {'x-refresh-token': refresh!});
      final problem = expectStatus(res, 200) ?? missing(res.json, ['redirect_url']);
      if (problem != null) return problem;
      final after = await send('POST', '/auth/refresh', headers: {'x-refresh-token': refresh!});
      return after.status == 401 ? null : 'refresh after logout: expected HTTP 401, got ${after.status}';
    });
  }

  /// Speaks just enough engine.io v4 and socket.io v4 over a WebSocket to send
  /// the "auth" event and return the first event the server sends back.
  Future<({String name, Object? payload})?> _socketAuth(String token) async {
    final uri = Uri.parse(base);
    final wsUri = uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '${uri.path}/socket.io/',
      queryParameters: {'EIO': '4', 'transport': 'websocket'},
    );
    final socket = await WebSocket.connect(wsUri.toString()).timeout(const Duration(seconds: 10));
    final reply = Completer<({String name, Object? payload})?>();
    final subscription = socket.listen(
      (Object? message) {
        if (message is! String || reply.isCompleted) return;
        if (message.startsWith('0')) {
          socket.add('40'); // engine.io open: join the default namespace
        } else if (message == '2') {
          socket.add('3'); // engine.io ping
        } else if (message.startsWith('40')) {
          socket.add('42${jsonEncode(['auth', token])}');
        } else if (message.startsWith('42')) {
          final event = jsonDecode(message.substring(2)) as List<dynamic>;
          reply.complete((name: event.first as String, payload: event.length > 1 ? event[1] : null));
        }
      },
      onDone: () {
        if (!reply.isCompleted) reply.complete(null);
      },
      onError: (Object _) {
        if (!reply.isCompleted) reply.complete(null);
      },
    );
    final result = await reply.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    await subscription.cancel();
    await socket.close();
    return result;
  }
}
