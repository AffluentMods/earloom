// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:typed_data';

/// A chapter marker found inside one file, on that file's own timeline.
final class TagChapter {
  const TagChapter({required this.start, this.end, this.title});

  final Duration start;

  /// Null when the format only stores start times.
  final Duration? end;
  final String? title;

  @override
  String toString() => 'TagChapter($start, $end, $title)';
}

/// An embedded picture.
final class TagPicture {
  const TagPicture(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

/// What the tags of one audio file say, already normalized across formats.
/// Plain data, so it can cross isolates.
final class FileTags {
  const FileTags({
    this.title,
    this.album,
    this.albumArtist,
    this.artist,
    this.composer,
    this.narrator,
    this.subtitle,
    this.description,
    this.publisher,
    this.language,
    this.year,
    this.series,
    this.seriesPart,
    this.genres = const [],
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.chapters = const [],
    this.cover,
  });

  static const empty = FileTags();

  final String? title;
  final String? album;
  final String? albumArtist;
  final String? artist;
  final String? composer;

  /// From an explicit narrator tag (`NARRATOR`, `©nrt`), not the composer.
  final String? narrator;
  final String? subtitle;
  final String? description;
  final String? publisher;
  final String? language;

  /// Four digits, when the tags carry a date.
  final String? year;
  final String? series;
  final String? seriesPart;
  final List<String> genres;
  final int? trackNumber;
  final int? discNumber;

  /// Null when neither the tags nor the stream headers tell.
  final Duration? duration;
  final List<TagChapter> chapters;
  final TagPicture? cover;
}

/// Trims, drops empty strings and stray NULs.
String? cleanTag(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll('\u0000', ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// The first four-digit year in [value], if any.
String? yearOf(String? value) {
  if (value == null) return null;
  final match = RegExp(r'(?<!\d)(1[5-9]\d\d|2\d\d\d)(?!\d)').firstMatch(value);
  return match?[1];
}

/// Parses "3", "03", "3/12" to 3. Zero and garbage are null.
int? leadingNumber(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^\s*(\d{1,4})').firstMatch(value);
  if (match == null) return null;
  final number = int.parse(match[1]!);
  return number == 0 ? null : number;
}
