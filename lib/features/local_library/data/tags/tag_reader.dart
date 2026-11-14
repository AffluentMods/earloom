// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;

import 'file_tags.dart';
import 'id3_frames.dart';
import 'mp4_atoms.dart';
import 'mpeg_audio.dart';

/// Reads the tags of one audio file. Synchronous and file-heavy: run it in a
/// background isolate. Never throws: a file whose tags cannot be read gives
/// [FileTags.empty] (plus a duration when the stream headers tell one).
///
/// `audio_metadata_reader` does most of the work. What it misses for
/// audiobooks is filled in here:
/// - MP3: chapters (ID3 `CHAP`) and a correct duration;
/// - MP4/M4B: album artist, composer, description, narrator and series
///   items, and QuickTime chapter tracks;
/// - FLAC/Ogg/Opus: chapters from `CHAPTERxxx` comments;
/// - raw AAC (ADTS): the duration, the library has no parser for it.
FileTags readFileTags(String path, {bool withCover = true}) {
  final file = File(path);
  Object? parsed;
  try {
    parsed = amr.readAllMetadata(file, getImage: withCover);
  } on Object {
    parsed = null;
  }
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    return switch (parsed) {
      amr.Mp3Metadata m => _fromMp3(m, raf),
      amr.Mp4Metadata m => _fromMp4(m, raf),
      amr.VorbisMetadata m => _fromVorbis(m),
      amr.RiffMetadata m => _fromRiff(m),
      amr.ApeMetadata m => _fromApe(m),
      _ => _fromStreamOnly(raf),
    };
  } on Object {
    return FileTags.empty;
  } finally {
    raf?.closeSync();
  }
}

FileTags _fromMp3(amr.Mp3Metadata m, RandomAccessFile raf) {
  final id3 = readId3Info(raf);
  final custom = {for (final e in m.customMetadata.entries) e.key.trim().toUpperCase(): e.value};
  // Raw AAC with an ID3 tag in front lands here too: count ADTS frames then.
  final duration =
      readMp3Duration(raf, audioStart: id3.tagLength) ??
      readAdtsDuration(raf, audioStart: id3.tagLength) ??
      _positive(m.duration);
  final comment = m.comments.map((c) => cleanTag(c.text)).nonNulls.firstOrNull;
  return FileTags(
    title: cleanTag(m.songName),
    album: cleanTag(m.album),
    albumArtist: cleanTag(m.bandOrOrchestra),
    artist: cleanTag(m.leadPerformer) ?? cleanTag(m.originalArtist),
    composer: cleanTag(m.composer),
    narrator: _first(custom, const ['NARRATOR', 'NARRATEDBY', 'READER']),
    subtitle: cleanTag(m.subtitle) ?? _first(custom, const ['SUBTITLE']),
    description: _first(custom, const ['DESCRIPTION', 'SUMMARY']) ?? comment ?? _first(custom, const ['COMMENT']),
    publisher: cleanTag(m.publisher),
    language: cleanTag(m.languages),
    year: yearOf('${m.originalReleaseYear ?? m.year ?? ''}') ?? yearOf(m.recordingDates) ?? yearOf(m.date),
    series: _first(custom, const ['SERIES', 'MVNM']),
    seriesPart: _first(custom, const ['SERIES-PART', 'SERIES_PART', 'SERIESPART', 'MVIN']),
    genres: _genres(m.genres),
    trackNumber: m.trackNumber == 0 ? null : m.trackNumber,
    discNumber: m.discNumber == 0 ? null : (m.discNumber ?? leadingNumber(m.partOfSet)),
    duration: duration,
    chapters: id3.chapters,
    cover: _cover(m.pictures),
  );
}

FileTags _fromMp4(amr.Mp4Metadata m, RandomAccessFile raf) {
  final extras = readMp4Extras(raf);
  final items = extras.items;
  String? item(String key) => cleanTag(items[key]);
  // Both chapter formats are often written together. The QuickTime track is
  // what Apple players show, so it wins when both exist.
  final chapters = extras.chapters.isNotEmpty
      ? extras.chapters
      : [for (final c in m.chapters) TagChapter(start: c.start, title: cleanTag(c.title))];
  return FileTags(
    title: cleanTag(m.title),
    album: cleanTag(m.album),
    albumArtist: item('aART'),
    artist: cleanTag(m.artist),
    composer: item('©wrt'),
    narrator: item('©nrt') ?? item('----:NARRATOR') ?? item('----:NARRATEDBY'),
    subtitle: item('----:SUBTITLE') ?? item('©st3'),
    description: item('ldes') ?? item('desc') ?? item('----:DESCRIPTION') ?? item('©cmt'),
    publisher: item('©pub') ?? item('----:PUBLISHER'),
    language: item('----:LANGUAGE'),
    year: yearOf(m.year?.year.toString()) ?? yearOf(item('©day')),
    series: item('©mvn') ?? item('----:SERIES'),
    seriesPart: item('©mvi') ?? item('----:SERIES-PART') ?? item('----:SERIES_PART'),
    genres: _genres([?m.genre]),
    trackNumber: m.trackNumber == 0 ? null : m.trackNumber,
    discNumber: m.discNumber == 0 ? null : m.discNumber,
    duration: _positive(m.duration),
    chapters: chapters,
    cover: _cover([?m.picture]),
  );
}

FileTags _fromVorbis(amr.VorbisMetadata m) {
  String? first(List<String> values) => values.map(cleanTag).nonNulls.firstOrNull;
  String? unknown(List<String> keys) => _first(m.unknowns, keys);
  return FileTags(
    title: first(m.title),
    album: first(m.album),
    albumArtist: first(m.albumArtist),
    artist: first(m.artist),
    composer: first(m.composer),
    narrator: unknown(const ['NARRATOR', 'NARRATEDBY', 'READER']) ?? first(m.performer),
    subtitle: unknown(const ['SUBTITLE']),
    description: first(m.description) ?? first(m.comment),
    publisher: first(m.organization),
    language: first(m.language),
    year: m.date.isEmpty ? null : yearOf('${m.date.first.year}'),
    series: unknown(const ['SERIES']),
    seriesPart: unknown(const ['SERIES-PART', 'SERIES_PART', 'SERIESPART']),
    genres: _genres(m.genres),
    trackNumber: m.trackNumber.where((n) => n > 0).firstOrNull,
    discNumber: (m.discNumber ?? 0) > 0 ? m.discNumber : null,
    duration: _positive(m.duration),
    chapters: vorbisChapters(m.unknowns),
    cover: _cover(m.pictures),
  );
}

FileTags _fromRiff(amr.RiffMetadata m) {
  return FileTags(
    title: cleanTag(m.title),
    album: cleanTag(m.album),
    artist: cleanTag(m.artist),
    description: cleanTag(m.comment),
    publisher: cleanTag(m.publisher),
    year: m.year == null ? null : yearOf('${m.year!.year}'),
    genres: _genres([?m.genre]),
    trackNumber: (m.trackNumber ?? 0) > 0 ? m.trackNumber : null,
    duration: _positive(m.duration),
    cover: _cover(m.pictures),
  );
}

FileTags _fromApe(amr.ApeMetadata m) {
  return FileTags(
    title: cleanTag(m.title),
    album: cleanTag(m.album),
    albumArtist: cleanTag(m.albumArtist),
    artist: cleanTag(m.artist),
    composer: cleanTag(m.composer),
    description: cleanTag(m.comment),
    language: m.language.map(cleanTag).nonNulls.firstOrNull,
    year: m.date == null ? null : yearOf('${m.date!.year}'),
    genres: _genres(m.genres),
    trackNumber: (m.trackNumber ?? 0) > 0 ? m.trackNumber : null,
    discNumber: (m.discNumber ?? 0) > 0 ? m.discNumber : null,
    duration: _positive(m.duration),
    cover: _cover(m.pictures),
  );
}

/// No tags the library understands: at least try the stream headers.
FileTags _fromStreamOnly(RandomAccessFile raf) {
  final id3 = readId3Info(raf);
  final duration = readAdtsDuration(raf, audioStart: id3.tagLength) ?? readMp3Duration(raf, audioStart: id3.tagLength);
  return FileTags(duration: duration, chapters: id3.chapters);
}

/// `CHAPTER001=00:01:02.500` and `CHAPTER001NAME=Title` comments, the chapter
/// convention for Vorbis comments.
List<TagChapter> vorbisChapters(Map<String, String> comments) {
  final pattern = RegExp(r'^CHAPTER(\d{1,4})$');
  final chapters = <TagChapter>[];
  for (final entry in comments.entries) {
    final match = pattern.firstMatch(entry.key.toUpperCase());
    if (match == null) continue;
    final start = parseClockTime(entry.value);
    if (start == null) continue;
    final name = comments['CHAPTER${match[1]}NAME'] ?? comments['CHAPTER${match[1]}name'];
    chapters.add(TagChapter(start: start, title: cleanTag(name)));
  }
  chapters.sort((a, b) => a.start.compareTo(b.start));
  return chapters;
}

/// Parses "HH:MM:SS", "HH:MM:SS.mmm" or "MM:SS.mmm".
Duration? parseClockTime(String value) {
  final match = RegExp(r'^\s*(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,9}))?\s*$').firstMatch(value);
  if (match == null) return null;
  final hours = int.parse(match[1] ?? '0');
  final minutes = int.parse(match[2]!);
  final seconds = int.parse(match[3]!);
  final fraction = match[4] ?? '';
  final micros = fraction.isEmpty ? 0 : int.parse(fraction.padRight(6, '0').substring(0, 6));
  return Duration(hours: hours, minutes: minutes, seconds: seconds, microseconds: micros);
}

String? _first(Map<String, String> map, List<String> keys) {
  for (final key in keys) {
    final value = cleanTag(map[key]);
    if (value != null) return value;
  }
  return null;
}

List<String> _genres(List<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      for (final part in value.split(RegExp(r'[;/\u0000]')))
        if (cleanTag(part) case final genre? when seen.add(genre.toLowerCase())) genre,
  ];
}

Duration? _positive(Duration? value) => value == null || value <= Duration.zero ? null : value;

/// The front cover if there is one, else the first picture.
TagPicture? _cover(List<amr.Picture> pictures) {
  if (pictures.isEmpty) return null;
  final front = pictures.where((p) => p.pictureType == amr.PictureType.coverFront).firstOrNull ?? pictures.first;
  if (front.bytes.isEmpty) return null;
  return TagPicture(front.bytes, front.mimetype);
}
