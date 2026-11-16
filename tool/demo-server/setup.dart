// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Sets up the demo server: the root user, an Audiobooks library over the
// LibriVox books from fetch_books.sh, and the `reviewer` user for App Review
// and Play review (normal user: can listen and download, cannot change or
// delete anything). Passwords are generated into tool/demo-server/.env
// (git-ignored) and never printed.
//
// From the repo root, with the server running (docker compose up -d in
// this folder):
//   dart run tool/demo-server/setup.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  final base = Uri.parse(
    args
        .firstWhere((a) => a.startsWith('--url='), orElse: () => '--url=http://127.0.0.1:13380')
        .substring('--url='.length),
  );
  final dir = File.fromUri(Platform.script).parent;
  final envFile = File('${dir.path}/.env');
  final env = await _loadOrCreateEnv(envFile);
  final api = _Api(base);

  stdout.writeln('Waiting for Audiobookshelf at $base ...');
  await api.waitForPing();

  final status = await api.getJson('/status');
  if (status['isInit'] != true) {
    stdout.writeln('Creating the root user ...');
    await api.post('/init', {
      'newRoot': {'username': 'root', 'password': env['DEMO_ROOT_PASSWORD']},
    });
  }
  await api.login('root', env['DEMO_ROOT_PASSWORD']!);

  final libraries = ((await api.getJson('/api/libraries'))['libraries'] as List).cast<Map<String, dynamic>>();
  var booksId = libraries.where((l) => l['name'] == 'Audiobooks').map((l) => l['id'] as String).firstOrNull;
  if (booksId == null) {
    stdout.writeln('Creating the Audiobooks library ...');
    final created = await api.post('/api/libraries', {
      'name': 'Audiobooks',
      'folders': [
        {'fullPath': '/audiobooks'},
      ],
      'mediaType': 'book',
      'icon': 'audiobookshelf',
    });
    booksId = (created! as Map<String, dynamic>)['id'] as String;
  }

  final users = ((await api.getJson('/api/users'))['users'] as List).cast<Map<String, dynamic>>();
  if (!users.any((u) => u['username'] == 'reviewer')) {
    stdout.writeln('Creating the "reviewer" user ...');
    await api.post('/api/users', {
      'username': 'reviewer',
      'password': env['DEMO_REVIEWER_PASSWORD'],
      'type': 'user',
      'isActive': true,
      'permissions': {'download': true, 'update': false, 'delete': false, 'upload': false},
    });
  }

  stdout.writeln('Scanning the library ...');
  await api.post('/api/libraries/$booksId/scan', null);
  await api.waitForItems(booksId);

  stdout.writeln('');
  stdout.writeln('Ready. Users: root (admin) and reviewer (normal user).');
  stdout.writeln('Their passwords are in ${envFile.path} (git-ignored).');
  stdout.writeln('Next: ./snapshot.sh in tool/demo-server, then the nightly reset (README.md).');
  exit(0);
}

Future<Map<String, String>> _loadOrCreateEnv(File file) async {
  final env = <String, String>{};
  final lines = await file.exists() ? await file.readAsLines() : <String>[];
  for (final line in lines) {
    final i = line.indexOf('=');
    if (i > 0 && !line.trimLeft().startsWith('#')) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final added = <String>[];
  for (final key in ['DEMO_ROOT_PASSWORD', 'DEMO_REVIEWER_PASSWORD']) {
    if ((env[key] ?? '').isEmpty) {
      env[key] = _randomPassword();
      added.add('$key=${env[key]}');
    }
  }
  if (added.isNotEmpty) {
    // Appends, so a TUNNEL_TOKEN already in the file stays.
    final header = lines.isEmpty ? '# Demo server secrets. Never commit this file.\n' : '';
    await file.writeAsString('$header${added.join('\n')}\n', mode: FileMode.append);
    stdout.writeln('Wrote new passwords to ${file.path}');
  }
  return env;
}

String _randomPassword() {
  const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(20, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}

class _Api {
  _Api(this.base);
  final Uri base;
  final _client = HttpClient();
  String? _accessToken;

  Uri _uri(String path) => base.resolve(path.startsWith('/') ? path.substring(1) : path);

  Future<void> waitForPing() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      try {
        final res = await (await _client.getUrl(_uri('/ping'))).close();
        await res.drain<void>();
        if (res.statusCode == 200) return;
      } on IOException {
        // Not up yet.
      }
      if (DateTime.now().isAfter(deadline)) {
        stderr.writeln('No answer from $base. Start it with: docker compose up -d (in tool/demo-server).');
        exit(1);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> login(String username, String password) async {
    final res = await _send(
      'POST',
      '/login',
      {'username': username, 'password': password},
      {'x-return-tokens': 'true'},
    );
    _accessToken = ((res! as Map<String, dynamic>)['user'] as Map<String, dynamic>)['accessToken'] as String;
  }

  Future<Map<String, dynamic>> getJson(String path) async =>
      (await _send('GET', path, null, const {}))! as Map<String, dynamic>;

  Future<Object?> post(String path, Object? body) => _send('POST', path, body, const {});

  Future<void> waitForItems(String libraryId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (true) {
      final page = await getJson('/api/libraries/$libraryId/items?limit=1');
      if ((page['total'] as int) > 0) {
        stdout.writeln('The library has ${page['total']} books so far (the scan may still be running).');
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        stderr.writeln('No books found. Run ./fetch_books.sh first, then check: docker logs earloom-demo');
        exit(1);
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<Object?> _send(String method, String path, Object? body, Map<String, String> headers) async {
    final req = await _client.openUrl(method, _uri(path));
    headers.forEach(req.headers.set);
    if (_accessToken != null) req.headers.set('Authorization', 'Bearer $_accessToken');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // The body of a failed call is a short plain-text reason, never a token.
      stderr.writeln('$method $path failed: HTTP ${res.statusCode} $text');
      exit(1);
    }
    if (text.isEmpty || !(res.headers.contentType?.mimeType.contains('json') ?? false)) return null;
    return jsonDecode(text);
  }
}
