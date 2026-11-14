// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/local_library/data/book_assembly.dart';
import 'package:earloom/features/local_library/data/tags/file_tags.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('track order', () {
    List<String> order(List<TaggedFile> files) => [for (final f in orderFiles(files)) f.path];

    test('disc, then track, then natural name', () {
      final files = [
        tagged('b.mp3', tags: const FileTags(discNumber: 2, trackNumber: 1)),
        tagged('c.mp3', tags: const FileTags(discNumber: 1, trackNumber: 2)),
        tagged('a.mp3', tags: const FileTags(discNumber: 1, trackNumber: 1)),
      ];
      expect(order(files), ['a.mp3', 'c.mp3', 'b.mp3']);
    });

    test('track numbers beat file names', () {
      final files = [
        tagged('01 Last.mp3', tags: const FileTags(trackNumber: 3)),
        tagged('02 First.mp3', tags: const FileTags(trackNumber: 1)),
        tagged('03 Middle.mp3', tags: const FileTags(trackNumber: 2)),
      ];
      expect(order(files), ['02 First.mp3', '03 Middle.mp3', '01 Last.mp3']);
    });

    test('without tags, natural name order: 2 before 10', () {
      expect(order([tagged('10.mp3'), tagged('2.mp3'), tagged('1.mp3')]), ['1.mp3', '2.mp3', '10.mp3']);
    });

    test('the part folder stands in for a missing disc tag', () {
      final files = [
        tagged('CD2/01.mp3', part: 2, tags: const FileTags(trackNumber: 1)),
        tagged('CD1/02.mp3', part: 1, tags: const FileTags(trackNumber: 2)),
        tagged('CD1/01.mp3', part: 1, tags: const FileTags(trackNumber: 1)),
      ];
      expect(order(files), ['CD1/01.mp3', 'CD1/02.mp3', 'CD2/01.mp3']);
    });

    test('numbered tracks come before unnumbered ones, equal tracks fall back to names', () {
      final files = [
        tagged('z.mp3'),
        tagged('b.mp3', tags: const FileTags(trackNumber: 1)),
        tagged('a.mp3', tags: const FileTags(trackNumber: 1)),
      ];
      expect(order(files), ['a.mp3', 'b.mp3', 'z.mp3']);
    });
  });

  group('metadata', () {
    test('title: album, then folder, then file name', () {
      expect(
        assembleMetadata([tagged('a.mp3', tags: const FileTags(album: 'The Album'))], folderName: 'F').title,
        'The Album',
      );
      expect(assembleMetadata([tagged('a.mp3'), tagged('b.mp3')], folderName: 'The Folder').title, 'The Folder');
      expect(assembleMetadata([tagged('First File.mp3'), tagged('b.mp3')]).title, 'First File');
    });

    test('a single file uses its title tag before the folder name', () {
      final meta = assembleMetadata([tagged('x.m4b', tags: const FileTags(title: 'Tag Title'))], folderName: 'F');
      expect(meta.title, 'Tag Title');
    });

    test('a multi-file book does not take a chapter title as its title', () {
      final meta = assembleMetadata([
        tagged('1.mp3', tags: const FileTags(title: 'Chapter One')),
        tagged('2.mp3', tags: const FileTags(title: 'Chapter Two')),
      ], folderName: 'Real Title');
      expect(meta.title, 'Real Title');
    });

    test('author: album artist, then artist', () {
      expect(
        assembleMetadata([
          tagged(
            'a.mp3',
            tags: const FileTags(albumArtist: 'Jane Example', artist: 'Other'),
          ),
        ]).authors,
        ['Jane Example'],
      );
      expect(assembleMetadata([tagged('a.mp3', tags: const FileTags(artist: 'Only Artist'))]).authors, ['Only Artist']);
      expect(assembleMetadata([tagged('a.mp3')]).authors, isEmpty);
    });

    test('narrator: explicit tag, then composer', () {
      expect(
        assembleMetadata([
          tagged(
            'a.mp3',
            tags: const FileTags(narrator: 'Sam Reader', composer: 'C'),
          ),
        ]).narrators,
        ['Sam Reader'],
      );
      expect(assembleMetadata([tagged('a.mp3', tags: const FileTags(composer: 'Theo Voice'))]).narrators, [
        'Theo Voice',
      ]);
    });

    test('values that differ between files take the most common', () {
      final meta = assembleMetadata([
        tagged('1.mp3', tags: const FileTags(album: 'Right')),
        tagged('2.mp3', tags: const FileTags(album: 'Wrong')),
        tagged('3.mp3', tags: const FileTags(album: 'Right')),
      ]);
      expect(meta.title, 'Right');
    });

    test('a description equal to the title is dropped', () {
      final meta = assembleMetadata([
        tagged(
          'a.m4b',
          tags: const FileTags(album: 'Same', description: 'Same'),
        ),
      ]);
      expect(meta.description, isNull);
    });

    test('splitNames splits on separators but never on commas', () {
      expect(splitNames('Jane Example; Sam Reader'), ['Jane Example', 'Sam Reader']);
      expect(splitNames('Jane Example/Sam Reader'), ['Jane Example', 'Sam Reader']);
      expect(splitNames('Jane Example & Sam Reader'), ['Jane Example', 'Sam Reader']);
      expect(splitNames('Example, Jane'), ['Example, Jane']);
      expect(splitNames('A\u0000B\u0000A'), ['A', 'B']);
      expect(splitNames(null), isEmpty);
    });
  });

  group('chapters', () {
    test('one chapter per file, titled from the tags, with running offsets', () {
      final result = buildChapters([
        tagged(
          '1.mp3',
          tags: const FileTags(title: 'Arrival', duration: Duration(seconds: 2)),
        ),
        tagged(
          '2.mp3',
          tags: const FileTags(title: 'Departure', duration: Duration(seconds: 3)),
        ),
      ], bookTitle: 'Book');
      expect(result.fromFiles, isTrue);
      expect(
        [for (final c in result.chapters) (c.title, c.start, c.end)],
        [
          ('Arrival', Duration.zero, const Duration(seconds: 2)),
          ('Departure', const Duration(seconds: 2), const Duration(seconds: 5)),
        ],
      );
    });

    test('titles that say nothing are left for the UI to number', () {
      final same = buildChapters([
        tagged(
          '1.mp3',
          tags: const FileTags(title: 'Book', duration: Duration(seconds: 1)),
        ),
        tagged(
          '2.mp3',
          tags: const FileTags(title: 'Book', duration: Duration(seconds: 1)),
        ),
      ], bookTitle: 'Other');
      expect(same.chapters.map((c) => c.title), [null, null]);
      final bookTitle = buildChapters([
        tagged(
          '1.mp3',
          tags: const FileTags(title: 'The Book', duration: Duration(seconds: 1)),
        ),
        tagged('2.mp3', tags: const FileTags(duration: Duration(seconds: 1))),
      ], bookTitle: 'the book');
      expect(bookTitle.chapters.map((c) => c.title), [null, null]);
    });

    test('embedded chapters, shifted per file, last one ending at the file end', () {
      final result = buildChapters([
        tagged(
          'part1.m4b',
          tags: const FileTags(
            duration: Duration(seconds: 10),
            chapters: [
              TagChapter(start: Duration.zero, title: 'One'),
              TagChapter(start: Duration(seconds: 4), title: 'Two'),
            ],
          ),
        ),
        tagged(
          'part2.mp3',
          tags: const FileTags(duration: Duration(seconds: 5), title: 'Bonus'),
        ),
      ], bookTitle: 'Book');
      expect(result.fromFiles, isFalse);
      expect(
        [for (final c in result.chapters) (c.title, c.start, c.end)],
        [
          ('One', Duration.zero, const Duration(seconds: 4)),
          ('Two', const Duration(seconds: 4), const Duration(seconds: 10)),
          ('Bonus', const Duration(seconds: 10), const Duration(seconds: 15)),
        ],
      );
    });

    test('chapters past the end are dropped, the first starts at zero', () {
      final result = buildChapters([
        tagged(
          'a.m4b',
          tags: const FileTags(
            duration: Duration(seconds: 10),
            chapters: [
              TagChapter(start: Duration(seconds: 1), title: 'Late start'),
              TagChapter(start: Duration(seconds: 12), title: 'Beyond'),
            ],
          ),
        ),
      ], bookTitle: 'Book');
      expect(
        [for (final c in result.chapters) (c.title, c.start, c.end)],
        [('Late start', Duration.zero, const Duration(seconds: 10))],
      );
    });
  });

  test('sourceFormatOf', () {
    expect(sourceFormatOf(['a.mp3', 'b.MP3']), 'mp3');
    expect(sourceFormatOf(['a.mp3', 'b.m4a']), 'mixed');
  });
}
