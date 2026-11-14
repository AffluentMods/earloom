// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/local_library/data/import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<String> paths(BookDraft book) => [for (final f in book.files) f.source.segments.join('/')];

void main() {
  group('picked files', () {
    test('several files are one book, in natural order, without a folder name', () {
      final draft = planImport(files(['10.mp3', '2.mp3', '1.mp3']));
      expect(draft.books, hasLength(1));
      expect(paths(draft.books.single), ['1.mp3', '2.mp3', '10.mp3']);
      expect(draft.books.single.folderName, isNull);
      expect(draft.books.single.displayName, '1');
    });

    test('a single m4b is one book', () {
      final draft = planImport(files(['The Quiet Harbor.m4b']));
      expect(draft.books.single.files, hasLength(1));
      expect(draft.books.single.displayName, 'The Quiet Harbor');
    });

    test('other files are skipped and reported, images are not', () {
      final draft = planImport(files(['a.mp3', 'notes.txt', 'cover.jpg', 'book.pdf']));
      expect(paths(draft.books.single), ['a.mp3']);
      expect(draft.skippedFiles, ['book.pdf', 'notes.txt']);
      expect(draft.books.single.coverImage?.name, 'cover.jpg');
    });

    test('nothing playable gives no books', () {
      final draft = planImport(files(['notes.txt']));
      expect(draft.books, isEmpty);
      expect(draft.skippedFiles, ['notes.txt']);
    });

    test('extensions match in any case', () {
      expect(planImport(files(['A.MP3', 'B.Opus'])).books.single.files, hasLength(2));
    });
  });

  group('picked folder', () {
    test('audio directly in the folder is one book named after it', () {
      final draft = planImport(folder('The Glass Orchard', ['02.mp3', '01.mp3', 'cover.jpg']));
      expect(draft.books, hasLength(1));
      expect(draft.books.single.folderName, 'The Glass Orchard');
      expect(paths(draft.books.single), ['01.mp3', '02.mp3']);
      expect(draft.books.single.coverImage?.name, 'cover.jpg');
    });

    test('sub-folders that each hold audio are one book each', () {
      final draft = planImport(
        folder('Audiobooks', ['Book Two/1.mp3', 'Book One/1.mp3', 'Book One/2.mp3', 'Book Two/folder.png']),
      );
      expect([for (final b in draft.books) b.folderName], ['Book One', 'Book Two']);
      expect(paths(draft.books.first), ['Book One/1.mp3', 'Book One/2.mp3']);
      expect(draft.books.last.coverImage?.name, 'folder.png');
    });

    test('CD, Disc and Part folders are parts of one book', () {
      final draft = planImport(
        folder('Long Book', ['CD2/01.mp3', 'CD1/02.mp3', 'CD1/01.mp3', 'CD10/01.mp3', 'cover.jpg']),
      );
      final book = draft.books.single;
      expect(book.folderName, 'Long Book');
      expect(paths(book), ['CD1/01.mp3', 'CD1/02.mp3', 'CD2/01.mp3', 'CD10/01.mp3']);
      expect([for (final f in book.files) f.partNumber], [1, 1, 2, 10]);
      expect(book.coverImage?.name, 'cover.jpg');
    });

    test('parts and direct audio together are still one book', () {
      final draft = planImport(folder('Book', ['00 Intro.mp3', 'Disc 1/01.mp3', 'Disc 2/01.mp3']));
      expect(draft.books.single.files, hasLength(3));
    });

    test('nested books are found at any depth', () {
      final draft = planImport(
        folder('Library', ['Author A/Series/Book 1/01.mp3', 'Author A/Series/Book 2/Part 1/01.mp3', 'Author B/x.m4b']),
      );
      expect([for (final b in draft.books) b.folderName], ['Book 1', 'Book 2', 'Author B']);
    });

    test('a cover inside a part folder is used when the book folder has none', () {
      final draft = planImport(folder('Book', ['CD1/01.mp3', 'CD1/front.jpg', 'CD2/01.mp3']));
      expect(draft.books.single.coverImage?.name, 'front.jpg');
    });

    test('macOS leftovers and hidden files are ignored', () {
      final draft = planImport(
        folder('Book', ['01.mp3', '._01.mp3', '__MACOSX/._02.mp3', '.hidden/03.mp3', 'Thumbs.db']),
      );
      expect(paths(draft.books.single), ['01.mp3']);
      expect(draft.skippedFiles, isEmpty);
    });

    test('an empty or audio-free folder gives no books', () {
      expect(planImport(folder('Empty', ['readme.txt'])).books, isEmpty);
    });
  });

  group('partNumberOf', () {
    test('recognizes part folders', () {
      expect(partNumberOf('CD1'), 1);
      expect(partNumberOf('CD 02'), 2);
      expect(partNumberOf('Disc 2'), 2);
      expect(partNumberOf('disk_3 of 4'), 3);
      expect(partNumberOf('Part 1 - The Start'), 1);
      expect(partNumberOf('Vol. 4'), 4);
    });

    test('does not mistake books for parts', () {
      expect(partNumberOf('1'), isNull);
      expect(partNumberOf('Partisan Tales'), isNull);
      expect(partNumberOf('Discovery 2'), isNull);
      expect(partNumberOf('The CD1 Mystery'), isNull);
    });
  });

  group('pickCoverImage', () {
    test('prefers conventional names, else a single image, else none', () {
      expect(pickCoverImage([FakeSourceFile('back.jpg'), FakeSourceFile('Cover.JPG')])?.name, 'Cover.JPG');
      expect(pickCoverImage([FakeSourceFile('art.png')])?.name, 'art.png');
      expect(pickCoverImage([FakeSourceFile('a.png'), FakeSourceFile('b.png')]), isNull);
      expect(pickCoverImage([]), isNull);
    });
  });
}
