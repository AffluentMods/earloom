// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/features/local_library/data/import_models.dart';
import 'package:earloom/features/local_library/data/import_source.dart';
import 'package:earloom/features/local_library/data/local_importer.dart';
import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:earloom/features/local_library/data/tags/file_tags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// Tolerance for durations: MP3 and AAC encoders pad the stream a little.
const _slack = Duration(milliseconds: 150);

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (actual) => (actual - expected).abs() <= _slack,
  'within ${_slack.inMilliseconds} ms of $expected',
);

Future<ImportOutcome> importAll(LocalImporter importer, ImportSelection selection) async {
  final plan = await importer.plan(selection);
  final outcome = await importer.start(plan.books).done;
  if (outcome.failed.isNotEmpty) fail('import failed: ${outcome.failed.map((f) => f.details).join('\n')}');
  return outcome;
}

Future<ImportSourceFile> source(File file, String root) =>
    IoImportFile.fromFile(file, segments: p.split(p.relative(file.path, from: root)));

Future<List<LocalFile>> filesOf(LocalDb db, String id) =>
    (db.select(db.localFiles)
          ..where((t) => t.bookId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
        .get();

Future<List<LocalChapter>> chaptersOf(LocalDb db, String id) =>
    (db.select(db.localChapters)
          ..where((t) => t.bookId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
        .get();

Future<LocalBook> bookOf(LocalDb db, String id) =>
    (db.select(db.localBooks)..where((t) => t.id.equals(id))).getSingle();

void main() {
  late LocalDb db;
  late LocalStorage storage;
  late LocalImporter importer;
  late Directory work;

  setUp(() async {
    db = memoryLocalDb();
    storage = await tempStorage();
    importer = LocalImporter(db: db, storage: storage);
    work = await Directory.systemTemp.createTemp('earloom_import_src_');
    addTearDown(() => work.delete(recursive: true));
  });

  group('with real audio', skip: ffmpegSkipReason, () {
    test('an MP3 set: tags, track order, durations, chapters, folder cover', () async {
      final dir = p.join(work.path, 'picked');
      const common = {
        'album': 'The Glass Orchard',
        'album_artist': 'Mira Example',
        'artist': 'Someone Else',
        'composer': 'Theo Reader',
        'date': '2019',
        'genre': 'Fiction',
      };
      final a = await makeMp3(p.join(dir, 'a.mp3'), seconds: 3, tags: {...common, 'track': '3', 'title': 'Departure'});
      final b = await makeMp3(p.join(dir, 'b.mp3'), seconds: 1, tags: {...common, 'track': '1', 'title': 'Arrival'});
      final c = await makeMp3(p.join(dir, 'c.mp3'), seconds: 2, tags: {...common, 'track': '2/3', 'title': 'Crossing'});
      final cover = await makeImage(p.join(dir, 'cover.jpg'));

      final outcome = await importAll(
        importer,
        PickedFiles([
          for (final f in [a, b, c, cover]) await source(f, dir),
        ]),
      );
      final id = outcome.added.single.bookId;
      expect(LocalStorage.isBookId(id), isTrue);

      final book = await bookOf(db, id);
      expect(book.title, 'The Glass Orchard');
      expect(book.authors, ['Mira Example']);
      expect(book.narrators, ['Theo Reader']);
      expect(book.publishedYear, '2019');
      expect(book.genres, ['Fiction']);
      expect(book.sourceFormat, 'mp3');
      expect(book.sizeBytes, await a.length() + await b.length() + await c.length());
      expect(book.chaptersFromFiles, isTrue);

      final files = await filesOf(db, id);
      expect(files.map((f) => f.originalName), ['b.mp3', 'c.mp3', 'a.mp3']);
      expect(files.map((f) => f.fileName), ['track_000.mp3', 'track_001.mp3', 'track_002.mp3']);
      expect(files.map((f) => f.trackNumber), [1, 2, 3]);
      expect(Duration(milliseconds: files[0].durationMs), closeToDuration(const Duration(seconds: 1)));
      expect(Duration(milliseconds: files[1].durationMs), closeToDuration(const Duration(seconds: 2)));
      expect(Duration(milliseconds: files[2].durationMs), closeToDuration(const Duration(seconds: 3)));
      expect(book.durationMs, files.fold(0, (sum, f) => sum + f.durationMs));

      // Copied byte for byte, originals left alone.
      for (final (file, original) in [(files[0], b), (files[1], c), (files[2], a)]) {
        final copy = storage.bookFile(id, file.fileName);
        expect(await copy.readAsBytes(), await original.readAsBytes());
      }
      expect(await a.exists(), isTrue);

      final chapters = await chaptersOf(db, id);
      expect(chapters.map((c) => c.title), ['Arrival', 'Crossing', 'Departure']);
      expect(chapters[0].startMs, 0);
      expect(chapters[1].startMs, files[0].durationMs);
      expect(chapters[2].startMs, files[0].durationMs + files[1].durationMs);
      expect(chapters[2].endMs, book.durationMs);

      expect(book.coverFile, matches(RegExp(r'^cover_\d+\.jpg$')));
      expect(await storage.bookFile(id, book.coverFile!).length(), await cover.length());

      // Nothing left in staging, nothing else in the book folder.
      final found = await storage.scan();
      expect(found.staging, isEmpty);
      expect(found.bookIds, [id]);
      final names = (await storage.bookDir(id).list().toList()).map((e) => p.basename(e.path)).toSet();
      expect(names, {'track_000.mp3', 'track_001.mp3', 'track_002.mp3', book.coverFile});
    });

    Future<File> makeM4b(String path, {bool quickTimeChaptersOnly = false}) async {
      final meta = File(p.join(work.path, 'meta.txt'));
      await meta.writeAsString(
        [
          ';FFMETADATA1',
          'title=The Quiet Harbor',
          'album=The Quiet Harbor',
          'artist=Jane Example',
          'album_artist=Jane Example',
          'composer=Sam Reader',
          'comment=A calm story.',
          'date=2021',
          for (final (start, end, title) in [(0, 2000, 'Opening'), (2000, 4000, 'The Middle'), (4000, 6000, 'Ending')])
            '\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=$start\nEND=$end\ntitle=$title',
        ].join('\n'),
      );
      final cover = await makeImage(p.join(work.path, 'art.png'), color: 'red');
      await ffmpeg([
        '-f', 'lavfi', '-i', 'sine=f=440:d=6', '-i', cover.path, '-i', meta.path, //
        '-map', '0:a', '-map', '1:v', '-map_metadata', '2', '-map_chapters', '2',
        '-c:a', 'aac', '-b:a', '32k', '-c:v', 'copy', '-disposition:v', 'attached_pic',
        if (quickTimeChaptersOnly) ...['-movflags', '+disable_chpl'],
        '-f', 'mp4', path,
      ]);
      return File(path);
    }

    test('a single M4B: embedded chapters, cover and iTunes items', () async {
      final m4b = await makeM4b(p.join(work.path, 'harbor.m4b'));
      final outcome = await importAll(importer, PickedFiles([await source(m4b, work.path)]));
      final id = outcome.added.single.bookId;
      final book = await bookOf(db, id);
      expect(book.title, 'The Quiet Harbor');
      expect(book.authors, ['Jane Example']);
      expect(book.narrators, ['Sam Reader']);
      expect(book.description, 'A calm story.');
      expect(book.publishedYear, '2021');
      expect(book.sourceFormat, 'm4b');
      expect(Duration(milliseconds: book.durationMs), closeToDuration(const Duration(seconds: 6)));
      expect(book.chaptersFromFiles, isFalse);

      final chapters = await chaptersOf(db, id);
      expect(chapters.map((c) => c.title), ['Opening', 'The Middle', 'Ending']);
      expect(chapters.map((c) => c.startMs), [0, 2000, 4000]);
      expect(chapters.last.endMs, book.durationMs);

      expect(book.coverFile, matches(RegExp(r'^cover_\d+\.png$')));
      final coverBytes = await storage.bookFile(id, book.coverFile!).readAsBytes();
      expect(coverBytes.sublist(1, 4), 'PNG'.codeUnits);
      expect((await filesOf(db, id)).single.fileName, 'track_000.m4b');
    });

    test('an M4B with only a QuickTime chapter track still has its chapters', () async {
      final m4b = await makeM4b(p.join(work.path, 'qt.m4b'), quickTimeChaptersOnly: true);
      final outcome = await importAll(importer, PickedFiles([await source(m4b, work.path)]));
      final chapters = await chaptersOf(db, outcome.added.single.bookId);
      expect(chapters.map((c) => c.title), ['Opening', 'The Middle', 'Ending']);
      expect(chapters.map((c) => c.startMs), [0, 2000, 4000]);
    });

    test('an MP3 with ID3 CHAP frames has its chapters', () async {
      final meta = File(p.join(work.path, 'chap.txt'));
      await meta.writeAsString(
        [
          ';FFMETADATA1',
          'album=Small Hours',
          for (final (start, end, title) in [(0, 1500, 'Dusk'), (1500, 3000, 'Night'), (3000, 4000, 'Dawn')])
            '\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=$start\nEND=$end\ntitle=$title',
        ].join('\n'),
      );
      final mp3 = p.join(work.path, 'hours.mp3');
      await ffmpeg([
        '-f', 'lavfi', '-i', 'sine=f=440:d=4', '-i', meta.path, //
        '-map', '0:a', '-map_metadata', '1', '-map_chapters', '1',
        '-c:a', 'libmp3lame', '-b:a', '32k', '-id3v2_version', '3', mp3,
      ]);
      final outcome = await importAll(importer, PickedFiles([await source(File(mp3), work.path)]));
      final id = outcome.added.single.bookId;
      final chapters = await chaptersOf(db, id);
      expect(chapters.map((c) => c.title), ['Dusk', 'Night', 'Dawn']);
      expect(chapters.map((c) => c.startMs), [0, 1500, 3000]);
      expect((await bookOf(db, id)).title, 'Small Hours');
    });

    test('a folder with disc sub-folders and a second book', () async {
      final root = p.join(work.path, 'Shelf');
      await makeMp3(p.join(root, 'Long Road', 'CD2', '01.mp3'), seconds: 1, tags: {'track': '1', 'title': 'Three'});
      await makeMp3(p.join(root, 'Long Road', 'CD1', '02.mp3'), seconds: 1, tags: {'track': '2', 'title': 'Two'});
      await makeMp3(p.join(root, 'Long Road', 'CD1', '01.mp3'), seconds: 1, tags: {'track': '1', 'title': 'One'});
      await makeImage(p.join(root, 'Long Road', 'folder.jpg'));
      await makeMp3(p.join(root, 'Short Trip', 'trip.mp3'), seconds: 1, tags: {'artist': 'Ada Example'});
      await File(p.join(root, 'Short Trip', 'notes.txt')).writeAsString('not audio');

      final sources = <ImportSourceFile>[
        await for (final e in Directory(root).list(recursive: true))
          if (e is File) await source(e, root),
      ];
      final plan = await importer.plan(PickedFolder('Shelf', sources));
      expect(plan.books.map((b) => b.displayName), ['Long Road', 'Short Trip']);
      expect(plan.skippedFiles, ['notes.txt']);
      final outcome = await importer.start(plan.books).done;
      expect(outcome.failed, isEmpty);
      expect(outcome.added.map((b) => b.title), ['Long Road', 'Short Trip']);

      final longRoad = outcome.added.first.bookId;
      final files = await filesOf(db, longRoad);
      expect(files.map((f) => f.originalName), ['01.mp3', '02.mp3', '01.mp3']);
      expect(files.map((f) => f.discNumber), [1, 1, 2]);
      expect((await chaptersOf(db, longRoad)).map((c) => c.title), ['One', 'Two', 'Three']);
      expect((await bookOf(db, longRoad)).coverFile, isNotNull);

      final shortTrip = await bookOf(db, outcome.added.last.bookId);
      expect(shortTrip.authors, ['Ada Example']);
      expect(shortTrip.coverFile, isNull);
    });

    test('importing the same files again is reported as a duplicate', () async {
      final dir = p.join(work.path, 'dup');
      final one = await makeMp3(p.join(dir, '1.mp3'), seconds: 1, tags: {'album': 'Twice Told'});
      final two = await makeMp3(p.join(dir, '2.mp3'), seconds: 1, tags: {'album': 'Twice Told'});
      Future<PickedFiles> pick() async => PickedFiles([await source(two, dir), await source(one, dir)]);

      final first = await importAll(importer, await pick());
      final again = await importer.plan(await pick());
      expect(again.duplicates, hasLength(1));
      expect(again.books.single.duplicateOf?.bookId, first.added.single.bookId);
      expect(again.books.single.duplicateOf?.title, 'Twice Told');

      // Different files are not duplicates.
      final other = await makeMp3(p.join(dir, '3.mp3'), seconds: 2);
      expect((await importer.plan(PickedFiles([await source(other, dir)]))).duplicates, isEmpty);
    });
  });

  group('failures and cancel', () {
    late LocalImporter fakeTags;
    setUp(() {
      fakeTags = LocalImporter(
        db: db,
        storage: storage,
        readTags: (paths) async => [for (final _ in paths) const FileTags(duration: Duration(seconds: 1))],
      );
    });

    Future<void> expectNothingLeft() async {
      expect(await db.select(db.localBooks).get(), isEmpty);
      expect(await db.select(db.localFiles).get(), isEmpty);
      final found = await storage.scan();
      expect(found.staging, isEmpty);
      expect(found.bookIds, isEmpty);
    }

    test('cancel while copying removes the partial copy and adds no rows', () async {
      final slow = _SlowSource('slow/01.mp3', chunks: 50);
      final plan = await fakeTags.plan(PickedFiles([slow]));
      final job = fakeTags.start(plan.books);
      final sub = job.progress.listen((progress) {
        if (progress.bookBytesDone > 0) job.cancel();
      });
      final outcome = await job.done;
      await sub.cancel();
      expect(outcome.cancelled, isTrue);
      expect(outcome.added, isEmpty);
      expect(slow.chunksRead, lessThan(50));
      await expectNothingLeft();
    });

    test('a book that fails is removed again, the next one is still imported', () async {
      final broken = FakeSourceFile('broken/01.mp3', size: 100);
      final plan = await fakeTags.plan(
        PickedFolder('root', [_FailingSource('broken/02.mp3'), broken, FakeSourceFile('fine/01.mp3', size: 50)]),
      );
      expect(plan.books, hasLength(2));
      final outcome = await fakeTags.start(plan.books).done;
      expect(outcome.failed.single.bookName, 'broken');
      expect(outcome.failed.single.kind, ImportErrorKind.unreadable);
      expect(outcome.failed.single.details, contains('gone'));
      expect(outcome.added.single.title, 'fine');
      final found = await storage.scan();
      expect(found.staging, isEmpty);
      expect(found.bookIds, [outcome.added.single.bookId]);
    });

    test('a file shorter than announced is an error, not a silent truncation', () async {
      final plan = await fakeTags.plan(PickedFiles([_ShortSource('a.mp3')]));
      final outcome = await fakeTags.start(plan.books).done;
      expect(outcome.failed.single.kind, ImportErrorKind.unreadable);
      await expectNothingLeft();
    });

    test('progress counts bytes up to the total', () async {
      final plan = await fakeTags.plan(
        PickedFiles([FakeSourceFile('a.mp3', size: 300), FakeSourceFile('b.mp3', size: 700)]),
      );
      final job = fakeTags.start(plan.books);
      final updates = <ImportProgress>[];
      final sub = job.progress.listen(updates.add);
      await job.done;
      await sub.cancel();
      expect(updates, isNotEmpty);
      expect(updates.last.allBytesTotal, 1000);
      expect(updates.last.allBytesDone, 1000);
      expect(
        updates.map((u) => u.stage),
        containsAllInOrder([ImportStage.copying, ImportStage.reading, ImportStage.saving]),
      );
    });

    test('leftovers of an interrupted import are cleaned before the next one', () async {
      const orphan = '11111111-2222-4333-8444-555555555555';
      await Directory(p.join(storage.root.path, '.import-$orphan')).create(recursive: true);
      await File(p.join(storage.bookDir(orphan).path, 'track_000.mp3')).create(recursive: true);
      await fakeTags.plan(PickedFiles([FakeSourceFile('a.mp3')]));
      await expectNothingLeft();
    });

    test('moving a temporary picker copy instead of copying it', () async {
      final temp = File(p.join(work.path, 'cache', 'picked.mp3'));
      await temp.create(recursive: true);
      await temp.writeAsBytes(List.filled(64, 1));
      final picked = await IoImportFile.fromFile(temp, isTemporaryCopy: true);
      final outcome = await fakeTags.start((await fakeTags.plan(PickedFiles([picked]))).books).done;
      expect(outcome.added, hasLength(1));
      expect(await temp.exists(), isFalse);
      final file = (await filesOf(db, outcome.added.single.bookId)).single;
      expect(await storage.bookFile(outcome.added.single.bookId, file.fileName).length(), 64);
    });
  });
}

class _SlowSource extends FakeSourceFile {
  _SlowSource(super.path, {required this.chunks}) : super(size: chunks * 1024);

  final int chunks;
  int chunksRead = 0;

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    if (start != null || end != null) {
      yield* super.openRead(start, end);
      return;
    }
    for (var i = 0; i < chunks; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      chunksRead++;
      yield List.filled(1024, i % 256);
    }
  }
}

class _FailingSource extends FakeSourceFile {
  _FailingSource(super.path) : super(size: 4096);

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    if (start != null || end != null) {
      yield* super.openRead(start, end);
      return;
    }
    yield List.filled(100, 1);
    throw const PathNotFoundException('broken/02.mp3', OSError('gone', 2));
  }
}

class _ShortSource extends FakeSourceFile {
  _ShortSource(super.path) : super(size: 200);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      start != null || end != null ? super.openRead(start, end) : Stream.value(List.filled(50, 1));
}
