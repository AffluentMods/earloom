// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:earloom/features/local_library/data/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  group('parsing helpers', () {
    test('parseClockTime', () {
      expect(parseClockTime('00:01:02.500'), const Duration(minutes: 1, seconds: 2, milliseconds: 500));
      expect(parseClockTime('1:00:00'), const Duration(hours: 1));
      expect(parseClockTime('02:03'), const Duration(minutes: 2, seconds: 3));
      expect(parseClockTime('nonsense'), isNull);
    });

    test('vorbisChapters pairs times with names and sorts them', () {
      final chapters = vorbisChapters({
        'CHAPTER002': '00:00:04.000',
        'CHAPTER002NAME': 'Ending',
        'CHAPTER001': '00:00:00.000',
        'CHAPTER001NAME': 'Opening',
        'CHAPTER003': 'broken',
      });
      expect(chapters.map((c) => (c.start, c.title)), [
        (Duration.zero, 'Opening'),
        (const Duration(seconds: 4), 'Ending'),
      ]);
    });

    test('a file that is not audio gives empty tags, never an error', () async {
      final dir = await Directory.systemTemp.createTemp('earloom_tags_');
      addTearDown(() => dir.delete(recursive: true));
      final junk = File(p.join(dir.path, 'junk.mp3'))..writeAsBytesSync(List.generate(5000, (i) => i * 7 % 256));
      final tags = readFileTags(junk.path);
      expect(tags.title, isNull);
      expect(tags.chapters, isEmpty);
    });
  });

  group('formats', skip: ffmpegSkipReason, () {
    late Directory dir;
    late File meta;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('earloom_formats_');
      meta = File(p.join(dir.path, 'meta.txt'));
      await meta.writeAsString(
        [
          ';FFMETADATA1',
          'title=Opening Night',
          'album=Paper Lanterns',
          'artist=Iris Example',
          'album_artist=Iris Example',
          'composer=Noah Voice',
          'track=4',
          'date=2018',
          '\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1000\ntitle=First',
          '\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1000\nEND=2000\ntitle=Second',
        ].join('\n'),
      );
    });
    tearDownAll(() => dir.delete(recursive: true));

    Future<String> encode(String name, List<String> codec) async {
      final path = p.join(dir.path, name);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'sine=f=440:d=2', '-i', meta.path, //
        '-map', '0:a', '-map_metadata', '1', '-map_chapters', '1', ...codec, path,
      ]);
      return path;
    }

    void expectAbout(Duration? actual, Duration expected) {
      expect(actual, isNotNull);
      expect((actual! - expected).abs(), lessThan(const Duration(milliseconds: 150)));
    }

    for (final (name, codec, hasChapters) in [
      ('a.flac', ['-c:a', 'flac'], false),
      ('a.ogg', ['-c:a', 'libvorbis'], false),
      ('a.opus', ['-c:a', 'libopus'], true),
      ('a.wav', <String>[], false),
      ('a.m4a', ['-c:a', 'aac', '-b:a', '32k'], true),
      ('a.mp3', ['-c:a', 'libmp3lame', '-b:a', '64k'], true),
    ]) {
      test('$name: title, album, people, duration${hasChapters ? ', chapters' : ''}', () async {
        final tags = readFileTags(await encode(name, codec));
        expect(tags.title, 'Opening Night');
        expect(tags.album, 'Paper Lanterns');
        expect(tags.artist, 'Iris Example');
        expectAbout(tags.duration, const Duration(seconds: 2));
        if (name != 'a.wav') {
          expect(tags.albumArtist, 'Iris Example');
          expect(tags.composer, 'Noah Voice');
          expect(tags.trackNumber, 4);
          expect(tags.year, '2018');
        }
        if (hasChapters) expect(tags.chapters.map((c) => c.title), ['First', 'Second']);
      });
    }

    test('raw AAC (ADTS): duration from the frames', () async {
      final tags = readFileTags(await encode('a.aac', ['-c:a', 'aac', '-b:a', '32k', '-f', 'adts']));
      expectAbout(tags.duration, const Duration(seconds: 2));
    });
  });
}
