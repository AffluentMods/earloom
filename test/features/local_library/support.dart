// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/features/local_library/data/import_planner.dart';
import 'package:earloom/features/local_library/data/import_source.dart';
import 'package:earloom/features/local_library/data/local_library_repository.dart';
import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:earloom/features/local_library/data/tags/file_tags.dart';
import 'package:earloom/features/local_library/data/book_assembly.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory source file: [segments] plus bytes.
class FakeSourceFile extends ImportSourceFile {
  FakeSourceFile(String path, {List<int>? bytes, int? size})
    : segments = path.split('/'),
      bytes = bytes ?? List<int>.filled(size ?? 10, 7);

  @override
  final List<String> segments;
  final List<int> bytes;

  @override
  int get size => bytes.length;

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    final from = start ?? 0;
    final to = (end ?? bytes.length).clamp(0, bytes.length);
    return Stream.value(bytes.sublist(from, to));
  }
}

PickedFolder folder(String name, List<String> paths) => PickedFolder(name, [for (final p in paths) FakeSourceFile(p)]);

PickedFiles files(List<String> names) => PickedFiles([for (final n in names) FakeSourceFile(n)]);

/// A tagged file for the pure assembly functions.
TaggedFile tagged(String path, {FileTags tags = FileTags.empty, int? part}) =>
    TaggedFile(DraftFile(FakeSourceFile(path), partNumber: part), tags);

/// An in-memory LocalDb, closed after the test.
LocalDb memoryLocalDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = LocalDb(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// A temporary `<support>/local` folder, deleted after the test.
Future<LocalStorage> tempStorage() async {
  final dir = await Directory.systemTemp.createTemp('earloom_local_test_');
  addTearDown(() => dir.delete(recursive: true));
  return LocalStorage(Directory('${dir.path}/local'));
}

const testStrings = LocalLibraryStrings(
  untitledChapter: _chapter,
  seriesLine: _series,
);

String _chapter(int n) => 'Chapter $n';
String _series(String series, String? sequence) => sequence == null ? series : 'Book $sequence of $series';

/// Why the ffmpeg based tests are skipped, or null when ffmpeg is there.
final String? ffmpegSkipReason = () {
  try {
    final result = Process.runSync('ffmpeg', ['-version']);
    return result.exitCode == 0 ? null : 'ffmpeg is not usable (exit ${result.exitCode})';
  } on ProcessException {
    return 'ffmpeg is not on PATH: these tests generate their audio with it';
  }
}();

/// Runs ffmpeg quietly and fails the test with its output on error.
Future<void> ffmpeg(List<String> args, {String? workingDirectory}) async {
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    ...args,
  ], workingDirectory: workingDirectory);
  if (result.exitCode != 0) fail('ffmpeg ${args.join(' ')}\n${result.stderr}');
}

/// A sine tone of [seconds] as MP3 with the given ID3 tags.
Future<File> makeMp3(String path, {required double seconds, Map<String, String> tags = const {}}) async {
  await File(path).parent.create(recursive: true);
  await ffmpeg([
    '-f', 'lavfi', '-i', 'sine=f=440:d=$seconds', //
    for (final e in tags.entries) ...['-metadata', '${e.key}=${e.value}'],
    '-c:a', 'libmp3lame', '-b:a', '32k', '-id3v2_version', '3', path,
  ]);
  return File(path);
}

/// A small solid color image.
Future<File> makeImage(String path, {String color = 'blue'}) async {
  await File(path).parent.create(recursive: true);
  await ffmpeg(['-f', 'lavfi', '-i', 'color=c=$color:s=32x32', '-frames:v', '1', path]);
  return File(path);
}

/// Waits for a stream to emit a value that matches.
Future<T> firstWhere<T>(Stream<T> stream, bool Function(T value) test) =>
    stream.firstWhere(test).timeout(const Duration(seconds: 10));
