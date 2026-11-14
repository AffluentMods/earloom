// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final storage = LocalStorage(Directory('/support/local'));
  const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';

  test('our own names', () {
    expect(LocalStorage.trackFileName(0, 'mp3'), 'track_000.mp3');
    expect(LocalStorage.trackFileName(1234, 'm4b'), 'track_1234.m4b');
    expect(
      LocalStorage.coverFileName(DateTime.fromMillisecondsSinceEpoch(1731571200000), 'jpg'),
      'cover_1731571200000.jpg',
    );
    expect(LocalStorage.isOwnFileName('track_000.mp3'), isTrue);
    expect(LocalStorage.isOwnFileName('cover_1731571200000.png'), isTrue);
  });

  test('a book folder is always directly inside the root', () {
    expect(storage.bookDir(id).path, '/support/local/$id');
    expect(storage.bookFile(id, 'track_001.mp3').path, '/support/local/$id/track_001.mp3');
    expect(storage.stagingDir(id).path, '/support/local/.import-$id');
  });

  test('anything that is not a book id is refused', () {
    for (final bad in ['..', '../etc', '$id/..', '', 'abc', '/tmp', '0B1C2D3E-4F50-4617-8899-AABBCCDDEEFF/../x']) {
      expect(() => storage.bookDir(bad), throwsArgumentError, reason: bad);
    }
  });

  test('file names from tags or the picker can never be used', () {
    for (final bad in [
      '../../evil.mp3',
      '/etc/passwd',
      'Chapter 1.mp3',
      'track_000.mp3/../../x',
      r'..\..\win.mp3',
      'track_000',
      '.hidden',
    ]) {
      expect(() => storage.bookFile(id, bad), throwsArgumentError, reason: bad);
    }
  });

  test('extensions must be plain', () {
    expect(() => LocalStorage.trackFileName(0, '../mp3'), throwsArgumentError);
    expect(() => LocalStorage.trackFileName(0, 'MP3'), throwsArgumentError);
  });
}
