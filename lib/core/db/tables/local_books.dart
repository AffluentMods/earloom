// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:drift/drift.dart';

/// A list of names (authors, narrators, genres) stored as a JSON array.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const [];
    return [
      for (final value in decoded)
        if (value is String) value,
    ];
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// One imported book (LocalDb). Its files live in `<support>/local/<id>/`.
///
/// Times are Unix epoch milliseconds, so sorting by them is exact.
@TableIndex(name: 'local_books_sort_title', columns: {#sortTitle})
@TableIndex(name: 'local_books_sort_author', columns: {#sortAuthor})
@TableIndex(name: 'local_books_added_at', columns: {#addedAtMs})
@TableIndex(name: 'local_books_fingerprint', columns: {#fingerprint})
class LocalBooks extends Table {
  /// A random UUID (v4). Also the name of the book's folder.
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get authors => text().map(const StringListConverter())();
  TextColumn get narrators => text().map(const StringListConverter())();
  TextColumn get seriesName => text().nullable()();

  /// As the user or the tags write it: "1", "2.5", "Book 2".
  TextColumn get seriesSequence => text().nullable()();

  /// Plain text or simple HTML from the tags. Render through the sanitizer.
  TextColumn get description => text().nullable()();
  TextColumn get genres => text().map(const StringListConverter())();
  TextColumn get publishedYear => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get language => text().nullable()();

  /// File name of the cover inside the book folder, like
  /// `cover_1731571200000.jpg`, or null. A new cover always gets a new name,
  /// so the name doubles as the cover key: image caches and cover colors
  /// refresh when it changes.
  TextColumn get coverFile => text().nullable()();

  /// Container of the audio, lower case: `m4b`, `mp3`, or `mixed`.
  TextColumn get sourceFormat => text()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  /// `<total audio bytes>:<sha256 of the first 64 KB of the first file>`,
  /// used to notice that the same files are imported twice.
  TextColumn get fingerprint => text()();

  /// True when the chapters were made from the files (one per file) because
  /// the tags had none. Such chapters follow file duration corrections.
  BoolColumn get chaptersFromFiles => boolean().withDefault(const Constant(true))();

  /// Folded, number-padded title for natural, case-insensitive sorting.
  TextColumn get sortTitle => text()();

  /// Folded first author, empty when there is none.
  TextColumn get sortAuthor => text()();

  /// Folded title, subtitle, authors, narrators and series, for search.
  TextColumn get searchText => text()();
  IntColumn get addedAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
