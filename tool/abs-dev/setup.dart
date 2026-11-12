// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Sets up the local Audiobookshelf dev server. Safe to run again at any time.
//
//   cd tool/abs-dev && docker compose up -d
//   dart run tool/abs-dev/setup.dart            (from the repo root)
//
// What it does:
//   1. Waits for the server on http://localhost:13378.
//   2. Generates the synthetic seed library inside the container, using the
//      ffmpeg that ships in the ABS image (nothing to install on the host).
//   3. Creates the root user, the two libraries and the `affluent` user.
//   4. Scans both libraries and waits for every seed item to show up.
//
// Passwords are generated once and kept in tool/abs-dev/.env.local, which is
// git-ignored. This script never prints them.
//
// Flags: --reseed  regenerate the audio even if it already exists.
//        --url=    use another base URL (default http://localhost:13378).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const container = 'abs-dev';

Future<void> main(List<String> args) async {
  final reseed = args.contains('--reseed');
  final base = Uri.parse(
    args
        .firstWhere((a) => a.startsWith('--url='), orElse: () => '--url=http://localhost:13378')
        .substring('--url='.length),
  );
  final dir = File.fromUri(Platform.script).parent;
  final env = await _loadOrCreateEnv(File('${dir.path}/.env.local'));
  final api = _Api(base);

  stdout.writeln('Waiting for Audiobookshelf at $base ...');
  await api.waitForPing();

  await _seed(reseed: reseed);

  final status = await api.getJson('/status');
  if (status['isInit'] != true) {
    stdout.writeln('Creating the root user ...');
    await api.post('/init', {
      'newRoot': {'username': 'root', 'password': env['ABS_ROOT_PASSWORD']},
    });
  }
  await api.login('root', env['ABS_ROOT_PASSWORD']!);

  final libraries = ((await api.getJson('/api/libraries'))['libraries'] as List).cast<Map<String, dynamic>>();
  Future<String> ensureLibrary(String name, String path, String mediaType, String icon) async {
    for (final l in libraries) {
      if (l['name'] == name) return l['id'] as String;
    }
    stdout.writeln('Creating library "$name" ...');
    final created = await api.post('/api/libraries', {
      'name': name,
      'folders': [
        {'fullPath': path},
      ],
      'mediaType': mediaType,
      'icon': icon,
    });
    return (created as Map<String, dynamic>)['id'] as String;
  }

  final booksId = await ensureLibrary('Audiobooks', '/audiobooks', 'book', 'audiobookshelf');
  final podcastsId = await ensureLibrary('Podcasts', '/podcasts', 'podcast', 'podcast');

  final users = ((await api.getJson('/api/users'))['users'] as List).cast<Map<String, dynamic>>();
  if (!users.any((u) => u['username'] == 'affluent')) {
    stdout.writeln('Creating the "affluent" user (no delete, no upload) ...');
    await api.post('/api/users', {
      'username': 'affluent',
      'password': env['ABS_AFFLUENT_PASSWORD'],
      'type': 'user',
      'isActive': true,
      'permissions': {'download': true, 'update': false, 'delete': false, 'upload': false},
    });
  }

  stdout.writeln('Scanning libraries ...');
  await api.post('/api/libraries/$booksId/scan', null);
  await api.post('/api/libraries/$podcastsId/scan', null);
  await api.waitForItems(booksId, _books.length);
  await api.waitForItems(podcastsId, _podcasts.length);

  stdout.writeln('');
  stdout.writeln('Ready: $base');
  stdout.writeln('  Users: root (admin) and affluent (normal user).');
  stdout.writeln('  Passwords are in tool/abs-dev/.env.local (git-ignored).');
  stdout.writeln(
    '  ${_books.length} books, ${_podcasts.length} podcast with ${_podcasts.first.episodes.length} episodes.',
  );
  exit(0);
}

// ---------------------------------------------------------------------------
// Seed data. Everything here is invented: no real titles, authors or audio.
// The audio is a quiet tone with a tick every second, enough to hear seeking.
// ---------------------------------------------------------------------------

class _Book {
  const _Book({
    required this.folder,
    required this.title,
    required this.author,
    required this.narrator,
    required this.layout,
    required this.minutes,
    required this.parts,
    required this.coverFrom,
    required this.coverTo,
    this.subtitle,
    this.series,
    this.genres = const ['Fiction'],
    this.tags = const [],
    this.year = '2024',
    this.description,
    this.coverWidth = 800,
    this.coverHeight = 800,
    this.embedCover = false,
  });

  /// Path under /audiobooks.
  final String folder;
  final String title;
  final String? subtitle;
  final String author;
  final String narrator;

  /// `mp3-files` (one file per chapter), `m4b` (one file, embedded chapters)
  /// or `opus-files` (one .opus file per chapter, to exercise transcoding).
  final String layout;
  final int minutes;

  /// Files for the multi-file layouts, chapters for `m4b`.
  final int parts;

  /// ABS sidecar format: "Series Name #sequence".
  final String? series;
  final List<String> genres;
  final List<String> tags;
  final String year;
  final String? description;
  final String coverFrom;
  final String coverTo;
  final int coverWidth;
  final int coverHeight;

  /// Put the cover inside the audio file instead of a cover.jpg next to it.
  final bool embedCover;
}

class _Podcast {
  const _Podcast({
    required this.folder,
    required this.title,
    required this.author,
    required this.episodes,
    required this.coverFrom,
    required this.coverTo,
  });
  final String folder;
  final String title;
  final String author;
  final List<String> episodes;
  final String coverFrom;
  final String coverTo;
}

const _hostileDescription =
    '<p>A slow, careful walk through <b>forty quiet places</b> and how to find '
    'your own. <i>Field notes</i>, maps and long silences.</p>'
    '<p>Second paragraph with a <a href="https://example.com/quiet">safe link</a>,<br>a line break, '
    'and things a client must never run or load:</p>'
    '<script>alert("description script")</script>'
    '<img src="x" onerror="alert(1)">'
    '<a href="javascript:alert(2)">a javascript link</a>'
    '<iframe src="https://example.com"></iframe>'
    '<p style="position:fixed;top:0">styled paragraph</p>'
    '<ul><li>First list item</li><li>Second list item</li></ul>'
    '<p>Final paragraph, long enough to need the collapse control. Lorem ipsum dolor sit amet, '
    'consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
    'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo '
    'consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat '
    'nulla pariatur.</p>';

const _books = <_Book>[
  _Book(
    folder: 'Mara Ellison/The Clockmaker\'s Tide',
    title: 'The Clockmaker\'s Tide',
    author: 'Mara Ellison',
    narrator: 'Jonah Pryce',
    layout: 'mp3-files',
    minutes: 32,
    parts: 8,
    genres: ['Fiction', 'Fantasy'],
    tags: ['multi-file'],
    description: '<p>A harbor town where every clock runs a little differently.</p>',
    coverFrom: '0x0B3954',
    coverTo: '0x087E8B',
  ),
  _Book(
    folder: 'Mara Ellison/Salt and Starlight',
    title: 'Salt and Starlight',
    subtitle: 'A Novel of the Outer Banks',
    author: 'Mara Ellison',
    narrator: 'Priya Castellan',
    layout: 'm4b',
    minutes: 45,
    parts: 9,
    genres: ['Fiction', 'Romance'],
    tags: ['single-file', 'embedded-cover'],
    description: '<p>One summer, one lighthouse, two people who should not get along.</p>',
    coverFrom: '0xFF5A5F',
    coverTo: '0xC81D25',
    embedCover: true,
  ),
  _Book(
    folder: 'Theo Vance/The Example Saga/Book 1 - Ember Road',
    title: 'Ember Road',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    layout: 'm4b',
    minutes: 12,
    parts: 4,
    series: 'The Example Saga #1',
    genres: ['Science Fiction'],
    description: '<p>Book one of The Example Saga.</p>',
    coverFrom: '0xF4A259',
    coverTo: '0xBC4B51',
  ),
  _Book(
    folder: 'Theo Vance/The Example Saga/Book 2 - Ash Harbor',
    title: 'Ash Harbor',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    layout: 'm4b',
    minutes: 12,
    parts: 4,
    series: 'The Example Saga #2',
    genres: ['Science Fiction'],
    description: '<p>Book two of The Example Saga.</p>',
    coverFrom: '0x5B8E7D',
    coverTo: '0x2F4858',
  ),
  _Book(
    folder: 'Theo Vance/The Example Saga/Book 2.5 - Cinder Interlude',
    title: 'Cinder Interlude',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    layout: 'm4b',
    minutes: 6,
    parts: 2,
    series: 'The Example Saga #2.5',
    genres: ['Science Fiction'],
    tags: ['novella'],
    description: '<p>A novella between books two and three.</p>',
    coverFrom: '0x8E5572',
    coverTo: '0x443850',
  ),
  _Book(
    folder: 'Theo Vance/The Example Saga/Book 10 - Kindling Sky',
    title: 'Kindling Sky',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    layout: 'm4b',
    minutes: 6,
    parts: 2,
    series: 'The Example Saga #10',
    genres: ['Science Fiction'],
    description: '<p>Book ten. It exists to prove that 10 sorts after 2.5.</p>',
    coverFrom: '0xE9C46A',
    coverTo: '0xE76F51',
  ),
  _Book(
    folder: 'Ines Okafor/A Field Guide to Quiet Places',
    title: 'A Field Guide to Quiet Places',
    author: 'Ines Okafor',
    narrator: 'Ines Okafor',
    layout: 'mp3-files',
    minutes: 6,
    parts: 3,
    genres: ['Nonfiction', 'Nature'],
    tags: ['html-description'],
    year: '2019',
    description: _hostileDescription,
    // A nearly gray cover, to exercise the neutral color fallback.
    coverFrom: '0x8A8A8A',
    coverTo: '0x6E6E73',
  ),
  _Book(
    folder: 'Rafael Dorn/Lanterns Under the Ice',
    title: 'Lanterns Under the Ice',
    author: 'Rafael Dorn',
    narrator: 'Priya Castellan',
    layout: 'opus-files',
    minutes: 10,
    parts: 2,
    genres: ['Mystery'],
    tags: ['opus', 'tall-cover'],
    description: '<p>Opus audio in an Ogg container, for the transcode path. The cover is not square.</p>',
    coverFrom: '0x1D3557',
    coverTo: '0xA8DADC',
    coverWidth: 600,
    coverHeight: 900,
  ),
  _Book(
    folder: 'Rafael Dorn/The Long Way to Morning',
    title: 'The Long Way to Morning',
    author: 'Rafael Dorn',
    narrator: 'Jonah Pryce',
    layout: 'm4b',
    minutes: 310,
    parts: 31,
    genres: ['Fiction'],
    tags: ['long'],
    year: '2021',
    description: '<p>Over five hours in one file: for sleep timers, long seeks and soak tests.</p>',
    coverFrom: '0x3A0CA3',
    coverTo: '0xF72585',
  ),
];

const _podcasts = <_Podcast>[
  _Podcast(
    folder: 'Shelf Talk',
    title: 'Shelf Talk',
    author: 'Affluent Demo Network',
    episodes: ['Episode 1 - Pilot', 'Episode 2 - Dog Ears', 'Episode 3 - The Long Shelf'],
    coverFrom: '0x06D6A0',
    coverTo: '0x118AB2',
  ),
];

Future<void> _seed({required bool reseed}) async {
  final marker = await _dockerExec(['sh', '-c', 'cat /audiobooks/.seed-version 2>/dev/null || true']);
  const version = '1';
  if (!reseed && marker.trim() == version) {
    stdout.writeln('Seed library already generated (use --reseed to rebuild it).');
    return;
  }
  stdout.writeln('Generating the synthetic seed library (a few minutes, the long book takes most of it) ...');
  for (final b in _books) {
    stdout.writeln('  ${b.title}');
    await _makeBook(b);
  }
  for (final p in _podcasts) {
    stdout.writeln('  ${p.title} (podcast)');
    await _makePodcast(p);
  }
  await _dockerExec(['sh', '-c', 'echo $version > /audiobooks/.seed-version']);
}

Future<void> _makeBook(_Book b) async {
  final dir = '/audiobooks/${b.folder}';
  await _dockerExec(['rm', '-rf', dir]);
  await _dockerExec(['mkdir', '-p', dir]);
  final cover = b.embedCover ? '/tmp/seed-cover.jpg' : '$dir/cover.jpg';
  await _makeCover(cover, b.coverFrom, b.coverTo, b.coverWidth, b.coverHeight);

  final seconds = b.minutes * 60;
  final common = [
    '-metadata',
    'album=${b.title}',
    '-metadata',
    'artist=${b.author}',
    '-metadata',
    'album_artist=${b.author}',
    '-metadata',
    'composer=${b.narrator}',
    '-metadata',
    'date=${b.year}',
  ];
  switch (b.layout) {
    case 'mp3-files' || 'opus-files':
      final opus = b.layout == 'opus-files';
      final each = seconds ~/ b.parts;
      for (var i = 1; i <= b.parts; i++) {
        final n = i.toString().padLeft(2, '0');
        await _ffmpeg([
          ..._tone(each, 180.0 + 30 * i),
          ..._toneOut,
          if (opus) ...['-c:a', 'libopus', '-b:a', '24k'] else ...['-c:a', 'libmp3lame', '-b:a', '32k'],
          ...common,
          '-metadata',
          'title=Chapter $i',
          '-metadata',
          'track=$i/${b.parts}',
          '$dir/${b.title} - $n.${opus ? 'opus' : 'mp3'}',
        ]);
      }
    case 'm4b':
      final each = seconds / b.parts;
      final meta = StringBuffer(';FFMETADATA1\n');
      for (var i = 0; i < b.parts; i++) {
        meta
          ..writeln('[CHAPTER]')
          ..writeln('TIMEBASE=1/1000')
          ..writeln('START=${(each * i * 1000).round()}')
          ..writeln('END=${(each * (i + 1) * 1000).round()}')
          ..writeln('title=Chapter ${i + 1}');
      }
      await _dockerExec(['sh', '-c', 'cat > /tmp/seed-chapters.ffmeta'], stdin: meta.toString());
      await _ffmpeg([
        ..._tone(seconds, 220),
        '-i',
        '/tmp/seed-chapters.ffmeta',
        if (b.embedCover) ...['-i', cover],
        '-map',
        '0:a',
        if (b.embedCover) ...['-map', '2:v', '-c:v', 'mjpeg', '-disposition:v', 'attached_pic'],
        '-map_metadata',
        '1',
        '-map_chapters',
        '1',
        ..._toneOut,
        '-c:a',
        'aac',
        '-b:a',
        b.minutes > 120 ? '16k' : '32k',
        ...common,
        '-metadata',
        'title=${b.title}',
        '-f',
        'mp4',
        '$dir/${b.title}.m4b',
      ]);
    default:
      throw StateError('Unknown layout ${b.layout}');
  }

  // The ABS sidecar. It wins over embedded tags, so the library is predictable.
  final sidecar = const JsonEncoder.withIndent('  ').convert({
    'title': b.title,
    if (b.subtitle != null) 'subtitle': b.subtitle,
    'authors': [b.author],
    'narrators': [b.narrator],
    'series': [if (b.series != null) b.series],
    'genres': b.genres,
    'tags': b.tags,
    'publishedYear': b.year,
    'publisher': 'Affluent Demo Press',
    if (b.description != null) 'description': b.description,
    'language': 'English',
    'explicit': false,
    'abridged': false,
  });
  await _dockerExec(['sh', '-c', 'cat > "\$1"', 'sh', '$dir/metadata.json'], stdin: sidecar);
}

Future<void> _makePodcast(_Podcast p) async {
  final dir = '/podcasts/${p.folder}';
  await _dockerExec(['rm', '-rf', dir]);
  await _dockerExec(['mkdir', '-p', dir]);
  await _makeCover('$dir/cover.jpg', p.coverFrom, p.coverTo, 800, 800);
  for (var i = 0; i < p.episodes.length; i++) {
    await _ffmpeg([
      ..._tone(5 * 60, 260.0 + 40 * i),
      ..._toneOut,
      '-c:a',
      'libmp3lame',
      '-b:a',
      '32k',
      '-metadata',
      'title=${p.episodes[i]}',
      '-metadata',
      'album=${p.title}',
      '-metadata',
      'artist=${p.author}',
      '-metadata',
      'track=${i + 1}',
      '$dir/${p.episodes[i]}.mp3',
    ]);
  }
  final sidecar = const JsonEncoder.withIndent('  ').convert({
    'title': p.title,
    'author': p.author,
    'description': '<p>A made-up show about made-up books. Notes mention 0:45 and 2:30.</p>',
    'genres': ['Arts', 'Books'],
    'language': 'English',
    'explicit': false,
    'podcastType': 'episodic',
  });
  await _dockerExec(['sh', '-c', 'cat > "\$1"', 'sh', '$dir/metadata.json'], stdin: sidecar);
}

/// A quiet mono tone with a short tick every second.
List<String> _tone(int seconds, double hz) => [
  '-f',
  'lavfi',
  '-i',
  'sine=frequency=${hz.round()}:beep_factor=3:sample_rate=24000:duration=$seconds',
];

/// Output options that go with [_tone]. They must come after every input.
const _toneOut = ['-af', 'volume=-20dB', '-ac', '1'];

Future<void> _makeCover(String path, String from, String to, int w, int h) => _ffmpeg([
  '-f',
  'lavfi',
  '-i',
  'gradients=s=${w}x$h:c0=$from:c1=$to:nb_colors=2:x0=0:y0=0:x1=$w:y1=$h:speed=0.00001',
  '-frames:v',
  '1',
  '-update',
  '1',
  '-q:v',
  '3',
  path,
]);

Future<void> _ffmpeg(List<String> args) => _dockerExec(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', ...args]);

Future<String> _dockerExec(List<String> command, {String? stdin}) async {
  final process = await Process.start('docker', ['exec', if (stdin != null) '-i', container, ...command]);
  if (stdin != null) {
    process.stdin.write(stdin);
  }
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('Command failed inside the "$container" container: ${command.take(3).join(' ')} ...');
    stderr.writeln(await err);
    stderr.writeln('Is the server running? Start it with: docker compose up -d (in tool/abs-dev).');
    exit(1);
  }
  return out;
}

// ---------------------------------------------------------------------------

Future<Map<String, String>> _loadOrCreateEnv(File file) async {
  final env = <String, String>{};
  if (await file.exists()) {
    for (final line in await file.readAsLines()) {
      final i = line.indexOf('=');
      if (i > 0 && !line.trimLeft().startsWith('#')) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
  }
  var changed = false;
  for (final key in ['ABS_ROOT_PASSWORD', 'ABS_AFFLUENT_PASSWORD']) {
    if ((env[key] ?? '').isEmpty) {
      env[key] = _randomPassword();
      changed = true;
    }
  }
  if (changed) {
    await file.writeAsString(
      '# Dev server passwords. Generated by setup.dart. Never commit this file.\n'
      '${env.entries.map((e) => '${e.key}=${e.value}').join('\n')}\n',
    );
    stdout.writeln('Wrote new dev passwords to ${file.path}');
  }
  return env;
}

String _randomPassword() {
  const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)]).join();
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
        stderr.writeln('No answer from $base. Start the server with: docker compose up -d (in tool/abs-dev).');
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
    _accessToken = ((res as Map<String, dynamic>)['user'] as Map<String, dynamic>)['accessToken'] as String;
  }

  Future<Map<String, dynamic>> getJson(String path) async =>
      (await _send('GET', path, null, const {})) as Map<String, dynamic>;

  Future<Object?> post(String path, Object? body) => _send('POST', path, body, const {});

  Future<void> waitForItems(String libraryId, int expected) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (true) {
      final page = await getJson('/api/libraries/$libraryId/items?limit=1');
      if ((page['total'] as int) >= expected) return;
      if (DateTime.now().isAfter(deadline)) {
        stderr.writeln(
          'The scan found ${page['total']} of $expected items. Check the server logs: docker logs $container',
        );
        exit(1);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
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
