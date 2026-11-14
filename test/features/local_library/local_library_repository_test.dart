// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/local_library/data/import_source.dart';
import 'package:earloom/features/local_library/data/local_importer.dart';
import 'package:earloom/features/local_library/data/local_library_repository.dart';
import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:earloom/features/local_library/data/tags/file_tags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// A 1x1 PNG.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  late LocalDb db;
  late LocalStorage storage;
  late LocalLibraryRepository repo;
  var now = DateTime(2026, 11, 14, 9);

  /// Imports a fake book of files with the given durations and tags.
  Future<String> addBook(
    String folderName,
    List<int> seconds, {
    FileTags Function(int index)? tags,
    List<int>? sizes,
  }) async {
    final importer = LocalImporter(
      db: db,
      storage: storage,
      clock: () => now,
      readTags: (paths) async => [
        for (var i = 0; i < paths.length; i++)
          (tags?.call(i) ?? const FileTags()).withDuration(Duration(seconds: seconds[i])),
      ],
    );
    final selection = PickedFolder(folderName, [
      for (var i = 0; i < seconds.length; i++)
        FakeSourceFile('$folderName/${(i + 1).toString().padLeft(2, '0')}.mp3', size: sizes?[i] ?? 1000 + i),
    ]);
    final plan = await importer.plan(selection);
    final outcome = await importer.start(plan.books).done;
    expect(outcome.failed, isEmpty);
    now = now.add(const Duration(minutes: 1));
    return outcome.added.single.bookId;
  }

  setUp(() async {
    now = DateTime(2026, 11, 14, 9);
    db = memoryLocalDb();
    storage = await tempStorage();
    repo = LocalLibraryRepository(db: db, storage: storage, strings: testStrings, clock: () => now);
  });

  group('playable', () {
    test('file tracks with cumulative start offsets, chapters, cover, ref', () async {
      final id = await addBook('Three Parts', [60, 120, 30]);
      final book = await repo.playable(id);
      expect(book.ref, ItemRef(const LocalSource(), id));
      expect(book.ref, LocalLibraryRepository.refOf(id));
      expect(book.title, 'Three Parts');
      expect(book.tracks.map((t) => t.start), [
        Duration.zero,
        const Duration(seconds: 60),
        const Duration(seconds: 180),
      ]);
      expect(book.tracks.map((t) => t.duration.inSeconds), [60, 120, 30]);
      expect(book.duration, const Duration(seconds: 210));
      for (final track in book.tracks) {
        expect(track.uri.scheme, 'file');
        expect(File.fromUri(track.uri).existsSync(), isTrue);
        expect(p.isWithin(storage.bookDir(id).path, track.uri.toFilePath()), isTrue);
        expect(track.mimeType, 'audio/mpeg');
      }
      // No titles in the tags: the UI words fill in.
      expect(book.chapters.map((c) => c.title), ['Chapter 1', 'Chapter 2', 'Chapter 3']);
      expect(book.chapters[1].start, const Duration(seconds: 60));
      expect(book.startPosition, Duration.zero);
      expect(book.artworkUri, isNull);
    });

    test('series line and people', () async {
      final id = await addBook(
        'Saga',
        [10],
        tags: (_) => const FileTags(
          album: 'The Example Saga 2',
          albumArtist: 'Jane Example',
          composer: 'Sam Reader',
          series: 'The Example Saga',
          seriesPart: '2',
        ),
      );
      final book = await repo.playable(id);
      expect(book.author, 'Jane Example');
      expect(book.narrator, 'Sam Reader');
      expect(book.seriesLine, 'Book 2 of The Example Saga');
    });

    test('resumes at the saved position, from the start when finished', () async {
      final id = await addBook('Resume', [100]);
      await repo.writeProgress(id, position: const Duration(seconds: 42), duration: const Duration(seconds: 100));
      expect((await repo.playable(id)).startPosition, const Duration(seconds: 42));
      await repo.markFinished(id);
      expect((await repo.playable(id)).startPosition, Duration.zero);
    });

    test('missing files say so instead of failing in the player', () async {
      final id = await addBook('Gone', [10]);
      await storage.bookFile(id, 'track_000.mp3').delete();
      await expectLater(repo.playable(id), throwsA(isA<LocalBookUnavailable>()));
      await expectLater(repo.playable('00000000-0000-4000-8000-000000000000'), throwsA(isA<LocalBookNotFound>()));
    });
  });

  group('progress sink', () {
    test('report writes position, time and listened time', () async {
      final id = await addBook('Sink', [100]);
      final sink = (await repo.playable(id)).sink;
      await sink.report(position: const Duration(seconds: 10), listened: const Duration(seconds: 10), isPlaying: true);
      now = now.add(const Duration(seconds: 15));
      await sink.report(position: const Duration(seconds: 25), listened: const Duration(seconds: 15), isPlaying: true);
      final progress = await repo.watchProgress(id).first;
      expect(progress!.position, const Duration(seconds: 25));
      expect(progress.duration, const Duration(seconds: 100));
      expect(progress.isFinished, isFalse);
      expect(progress.updatedAt, now);
      final row = await db.select(db.localProgress).getSingle();
      expect(row.listenedMs, 25000);
      expect(row.lastPlayedAtMs, now.millisecondsSinceEpoch);
    });

    test('finished marks the book, close at the end keeps it finished', () async {
      final id = await addBook('End', [100]);
      final sink = (await repo.playable(id)).sink;
      await sink.finished(position: const Duration(seconds: 99, milliseconds: 800));
      await sink.close(position: const Duration(seconds: 100));
      final progress = await repo.watchProgress(id).first;
      expect(progress!.isFinished, isTrue);
      expect(progress.finishedAt, now);
      expect(progress.position, const Duration(seconds: 100));
    });

    test('playing a finished book again takes the mark off', () async {
      final id = await addBook('Again', [100]);
      await repo.markFinished(id);
      final sink = (await repo.playable(id)).sink;
      await sink.report(position: const Duration(seconds: 3), listened: const Duration(seconds: 3), isPlaying: true);
      final progress = await repo.watchProgress(id).first;
      expect(progress!.isFinished, isFalse);
      expect(progress.finishedAt, isNull);
    });

    test('close writes the final position', () async {
      final id = await addBook('Close', [100]);
      await (await repo.playable(id)).sink.close(position: const Duration(seconds: 61));
      expect((await repo.watchProgress(id).first)!.position, const Duration(seconds: 61));
    });
  });

  group('finished marks', () {
    test('mark finished and unfinished', () async {
      final id = await addBook('Marks', [100]);
      await repo.markFinished(id);
      var progress = await repo.watchProgress(id).first;
      expect(progress!.isFinished, isTrue);
      expect(progress.fraction, 1);
      await repo.markUnfinished(id);
      progress = await repo.watchProgress(id).first;
      expect(progress!.isFinished, isFalse);
      // It was at the very end: back to the start.
      expect(progress.position, Duration.zero);
    });

    test('unfinished keeps a position in the middle', () async {
      final id = await addBook('Middle', [100]);
      await repo.writeProgress(id, position: const Duration(seconds: 50), duration: const Duration(seconds: 100));
      await repo.markUnfinished(id);
      expect((await repo.watchProgress(id).first)!.position, const Duration(seconds: 50));
    });
  });

  group('delete', () {
    test('removes files and rows and says how much space it freed', () async {
      final id = await addBook('Big', [10, 10], sizes: [3000, 5000]);
      await repo.addBookmark(id, const Duration(seconds: 3), 'Mark');
      await repo.writeProgress(id, position: const Duration(seconds: 5), duration: const Duration(seconds: 20));
      expect(await repo.storageBytes(id), 8000);
      final freed = await repo.deleteBook(id);
      expect(freed, 8000);
      expect(await storage.bookDir(id).exists(), isFalse);
      expect(await db.select(db.localBooks).get(), isEmpty);
      expect(await db.select(db.localFiles).get(), isEmpty);
      expect(await db.select(db.localBookmarks).get(), isEmpty);
      expect(await db.select(db.localProgress).get(), isEmpty);
      expect(await repo.watchBook(id).first, isNull);
    });
  });

  group('bookmarks', () {
    test('add, rename, delete, list in position order', () async {
      final id = await addBook('Marks', [100]);
      await repo.addBookmark(id, const Duration(seconds: 50), 'Later');
      await repo.addBookmark(id, const Duration(seconds: 10), '  Earlier  ');
      expect((await repo.bookmarks(id)).map((b) => b.title), ['Earlier', 'Later']);
      await repo.renameBookmark(id, const Duration(seconds: 50), 'Renamed');
      expect((await repo.bookmarks(id)).last.title, 'Renamed');
      await repo.addBookmark(id, const Duration(seconds: 10), 'Same spot');
      expect((await repo.bookmarks(id)).map((b) => b.title), ['Same spot', 'Renamed']);
      await repo.deleteBookmark(id, const Duration(seconds: 10));
      final left = await repo.bookmarks(id);
      expect(left.single.position, const Duration(seconds: 50));
      expect(left.single.ref, LocalLibraryRepository.refOf(id));
    });
  });

  group('metadata', () {
    test('edit replaces fields and keeps search and sort in step', () async {
      final id = await addBook('Old Title', [10]);
      await repo.updateMetadata(
        id,
        const LocalBookEdit(
          title: '  New Title ',
          authors: ['Jane Example', ' ', 'jane example'],
          narrators: ['Sam Reader'],
          seriesName: 'Harbor Tales',
          seriesSequence: '3',
          description: 'About the sea.',
        ),
      );
      final detail = (await repo.watchBook(id).first)!;
      expect(detail.summary.title, 'New Title');
      expect(detail.summary.authors, ['Jane Example']);
      expect(detail.summary.narrators, ['Sam Reader']);
      expect(detail.summary.seriesName, 'Harbor Tales');
      expect(detail.summary.seriesSequence, '3');
      expect(detail.descriptionHtml, 'About the sea.');
      expect(detail.series.single.sequence, '3');
      expect(await repo.watchBooks(query: 'harbor').first, hasLength(1));
      expect(await repo.watchBooks(query: 'old title').first, isEmpty);
    });

    test('a series number without a series is dropped', () async {
      final id = await addBook('No Series', [10]);
      await repo.updateMetadata(id, const LocalBookEdit(title: 'No Series', seriesSequence: '4'));
      expect((await repo.watchBook(id).first)!.summary.seriesSequence, isNull);
    });

    test('a new cover gets a new key and file, the old one is removed', () async {
      final id = await addBook('Covers', [10]);
      final picked = File(p.join(storage.root.parent.path, 'picked.png'))..writeAsBytesSync(_png);
      await repo.updateMetadata(id, LocalBookEdit(title: 'Covers', coverImagePath: picked.path));
      final first = (await repo.watchBook(id).first)!.summary.coverKey;
      expect(first, matches(RegExp(r'^cover_\d+\.png$')));
      expect(repo.coverFile(id, first)!.existsSync(), isTrue);
      expect((await repo.playable(id)).artworkUri, repo.coverFile(id, first)!.uri);

      now = now.add(const Duration(seconds: 1));
      await repo.updateMetadata(id, LocalBookEdit(title: 'Covers', coverImagePath: picked.path));
      final second = (await repo.watchBook(id).first)!.summary.coverKey;
      expect(second, isNot(first));
      expect(repo.coverFile(id, first)!.existsSync(), isFalse);
      expect(repo.coverFile(id, second)!.existsSync(), isTrue);
    });

    test('a picture that is not an image is refused and nothing changes', () async {
      final id = await addBook('Text', [10]);
      final picked = File(p.join(storage.root.parent.path, 'fake.jpg'))..writeAsStringSync('not an image');
      await expectLater(
        repo.updateMetadata(id, LocalBookEdit(title: 'Changed', coverImagePath: picked.path)),
        throwsA(isA<UnsupportedCoverImage>()),
      );
      expect((await repo.watchBook(id).first)!.summary.title, 'Text');
    });

    test('an empty title is refused', () async {
      final id = await addBook('Kept', [10]);
      await expectLater(repo.updateMetadata(id, const LocalBookEdit(title: '  ')), throwsArgumentError);
    });

    test('coverFile only resolves our own names', () {
      const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
      expect(repo.coverFile(id, null), isNull);
      expect(repo.coverFile(id, '../../x.jpg'), isNull);
    });
  });

  group('watchBooks', () {
    test('sorts by title naturally, author, recently added and recently played', () async {
      final b2 = await addBook('Book 2', [10], tags: (_) => const FileTags(albumArtist: 'Zed Example'));
      final b10 = await addBook('Book 10', [10], tags: (_) => const FileTags(albumArtist: 'Amy Example'));
      final b1 = await addBook('book 1', [10]);

      Future<List<String>> ids(LocalBookSort sort) async => [
        for (final b in await repo.watchBooks(sort: sort).first) b.ref.itemId,
      ];

      expect(await ids(LocalBookSort.title), [b1, b2, b10]);
      expect(await ids(LocalBookSort.author), [b10, b2, b1]);
      expect(await ids(LocalBookSort.recentlyAdded), [b1, b10, b2]);

      await repo.writeProgress(b2, position: const Duration(seconds: 1), duration: const Duration(seconds: 10));
      now = now.add(const Duration(minutes: 1));
      await repo.writeProgress(b10, position: const Duration(seconds: 1), duration: const Duration(seconds: 10));
      expect(await ids(LocalBookSort.recentlyPlayed), [b10, b2, b1]);
    });

    test('search matches title, author, narrator and series, ignoring case and accents', () async {
      await addBook(
        'Émile and the Sea',
        [10],
        tags: (_) => const FileTags(albumArtist: 'Zoë Example', narrator: 'Theo Reader', series: 'Coastal'),
      );
      await addBook('Other', [10]);
      Future<int> count(String query) async => (await repo.watchBooks(query: query).first).length;
      expect(await count('emile'), 1);
      expect(await count('ZOE'), 1);
      expect(await count('reader'), 1);
      expect(await count('coastal'), 1);
      expect(await count('100%'), 0);
      expect(await count('_'), 0);
      expect(await count('  '), 2);
    });

    test('summaries carry progress, cover key and local flags', () async {
      final id = await addBook('Flags', [100]);
      await repo.writeProgress(id, position: const Duration(seconds: 30), duration: const Duration(seconds: 100));
      final summary = (await repo.watchBooks().first).single;
      expect(summary.isDownloaded, isTrue);
      expect(summary.isPodcast, isFalse);
      expect(summary.duration, const Duration(seconds: 100));
      expect(summary.progress!.fraction, closeTo(0.3, 0.001));
      expect(summary.addedAt, isNotNull);
    });

    test('the stream updates after an import', () async {
      final stream = repo.watchBooks();
      final seen = <int>[];
      final sub = stream.listen((books) => seen.add(books.length));
      await pumpEventQueue();
      await addBook('Live', [10]);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('duration corrections', () {
    test('file chapters follow the measured durations', () async {
      final id = await addBook('Wrong Tags', [10, 10]);
      await repo.correctFileDurations(id, const [Duration(seconds: 12), Duration(seconds: 8)]);
      final book = await repo.playable(id);
      expect(book.tracks.map((t) => t.start.inSeconds), [0, 12]);
      expect(book.duration, const Duration(seconds: 20));
      expect(book.chapters.map((c) => (c.start.inSeconds, c.end.inSeconds)), [(0, 12), (12, 20)]);
    });
  });
}

extension on FileTags {
  FileTags withDuration(Duration duration) => FileTags(
    title: title,
    album: album,
    albumArtist: albumArtist,
    artist: artist,
    composer: composer,
    narrator: narrator,
    series: series,
    seriesPart: seriesPart,
    trackNumber: trackNumber,
    duration: duration,
    chapters: chapters,
  );
}
