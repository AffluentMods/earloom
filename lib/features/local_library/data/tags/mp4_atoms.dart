// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'file_tags.dart';

/// What `audio_metadata_reader` does not read from MP4 files: the iTunes
/// items audiobooks rely on (album artist, composer, description, narrator,
/// series) and QuickTime chapter tracks, the chapter format Apple tools and
/// most audiobook converters write. The library only reads Nero `chpl`
/// chapters.
final class Mp4Extras {
  const Mp4Extras({this.items = const {}, this.chapters = const []});

  /// iTunes item values by atom name (`aART`, `©wrt`, `desc`...). Free-form
  /// `----` items are keyed `----:<NAME>` with the name upper-cased.
  final Map<String, String> items;

  /// From the QuickTime chapter track, empty when there is none.
  final List<TagChapter> chapters;
}

/// Largest `moov` box read into memory. Real audiobooks stay far below it
/// even with a large cover; anything bigger is not worth the memory.
const _maxMoovBytes = 64 * 1024 * 1024;
const _maxChapters = 10000;

/// Reads [Mp4Extras] from an MP4 file. Never throws on malformed input: what
/// cannot be parsed is left out.
Mp4Extras readMp4Extras(RandomAccessFile file) {
  try {
    final moov = _readTopLevelBox(file, 'moov');
    if (moov == null) return const Mp4Extras();
    final parser = _MoovParser(moov);
    parser.parse();
    return Mp4Extras(items: parser.items, chapters: _readQuickTimeChapters(file, parser.tracks));
  } on Object {
    return const Mp4Extras();
  }
}

Uint8List? _readTopLevelBox(RandomAccessFile file, String type) {
  final length = file.lengthSync();
  var pos = 0;
  while (pos + 8 <= length) {
    file.setPositionSync(pos);
    final header = file.readSync(16);
    if (header.length < 8) return null;
    final view = ByteData.sublistView(header);
    var size = view.getUint32(0);
    var headerSize = 8;
    final boxType = latin1.decode(header.sublist(4, 8));
    if (size == 1) {
      if (header.length < 16) return null;
      size = view.getUint64(8);
      headerSize = 16;
    } else if (size == 0) {
      size = length - pos;
    }
    if (size < headerSize || pos + size > length) return null;
    if (boxType == type) {
      final payload = size - headerSize;
      if (payload > _maxMoovBytes) return null;
      file.setPositionSync(pos + headerSize);
      return file.readSync(payload);
    }
    pos += size;
  }
  return null;
}

/// One box inside an in-memory buffer.
final class _Box {
  const _Box(this.type, this.start, this.end);

  final String type;

  /// Payload start and end (exclusive) in the buffer.
  final int start;
  final int end;
}

Iterable<_Box> _children(Uint8List data, int start, int end) sync* {
  final view = ByteData.sublistView(data);
  var pos = start;
  while (pos + 8 <= end) {
    var size = view.getUint32(pos);
    var headerSize = 8;
    final type = latin1.decode(data.sublist(pos + 4, pos + 8));
    if (size == 1) {
      if (pos + 16 > end) return;
      size = view.getUint64(pos + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < headerSize || pos + size > end) return;
    yield _Box(type, pos + headerSize, pos + size);
    pos += size;
  }
}

final class _Track {
  int id = 0;
  String handler = '';
  int timescale = 0;
  int durationUnits = 0;
  List<int> chapterTrackIds = const [];
  List<(int count, int delta)> timeToSample = const [];
  List<(int firstChunk, int samplesPerChunk)> sampleToChunk = const [];
  int uniformSampleSize = 0;
  List<int> sampleSizes = const [];
  int sampleCount = 0;
  List<int> chunkOffsets = const [];
}

final class _MoovParser {
  _MoovParser(this.data) : view = ByteData.sublistView(data);

  final Uint8List data;
  final ByteData view;
  final items = <String, String>{};
  final tracks = <_Track>[];

  void parse() {
    for (final box in _children(data, 0, data.length)) {
      switch (box.type) {
        case 'udta':
          _parseUdta(box);
        case 'trak':
          tracks.add(_parseTrack(box));
      }
    }
  }

  void _parseUdta(_Box udta) {
    for (final box in _children(data, udta.start, udta.end)) {
      if (box.type != 'meta') continue;
      // `meta` is a full box (4 bytes version and flags) in MP4, but some
      // writers leave those out. Look for a plausible child header first.
      var start = box.start;
      if (!_looksLikeBoxHeader(start, box.end)) start += 4;
      for (final child in _children(data, start, box.end)) {
        if (child.type == 'ilst') _parseIlst(child);
      }
    }
  }

  bool _looksLikeBoxHeader(int pos, int end) {
    if (pos + 8 > end) return false;
    final size = view.getUint32(pos);
    if (size < 8 || pos + size > end) return false;
    return data.sublist(pos + 4, pos + 8).every((b) => b >= 0x20 && b <= 0x7E);
  }

  void _parseIlst(_Box ilst) {
    for (final item in _children(data, ilst.start, ilst.end)) {
      if (item.type == '----') {
        String? name;
        String? value;
        for (final part in _children(data, item.start, item.end)) {
          if (part.type == 'name' && part.end - part.start > 4) {
            name = utf8.decode(data.sublist(part.start + 4, part.end), allowMalformed: true);
          } else if (part.type == 'data') {
            value = _dataValue(part);
          }
        }
        if (name != null && value != null) items['----:${name.trim().toUpperCase()}'] = value;
        continue;
      }
      for (final part in _children(data, item.start, item.end)) {
        if (part.type != 'data') continue;
        final value = _dataValue(part);
        if (value != null) items[item.type] = value;
        break;
      }
    }
  }

  /// The value of a `data` box: 1 byte version, 3 bytes type, 4 bytes
  /// locale, then the value. Text and integers only.
  String? _dataValue(_Box box) {
    if (box.end - box.start < 8) return null;
    final type = view.getUint32(box.start) & 0xFFFFFF;
    final value = data.sublist(box.start + 8, box.end);
    switch (type) {
      case 1:
        return utf8.decode(value, allowMalformed: true);
      case 2:
        return _decodeUtf16(value, bigEndian: true);
      case 21 || 22:
        if (value.isEmpty || value.length > 8) return null;
        var number = 0;
        for (final b in value) {
          number = (number << 8) | b;
        }
        return '$number';
      default:
        return null;
    }
  }

  _Track _parseTrack(_Box trak) {
    final track = _Track();
    for (final box in _children(data, trak.start, trak.end)) {
      switch (box.type) {
        case 'tkhd':
          final version = data[box.start];
          final idPos = box.start + (version == 1 ? 20 : 12);
          if (idPos + 4 <= box.end) track.id = view.getUint32(idPos);
        case 'tref':
          for (final ref in _children(data, box.start, box.end)) {
            if (ref.type != 'chap') continue;
            track.chapterTrackIds = [
              for (var p = ref.start; p + 4 <= ref.end; p += 4) view.getUint32(p),
            ];
          }
        case 'mdia':
          _parseMedia(box, track);
      }
    }
    return track;
  }

  void _parseMedia(_Box mdia, _Track track) {
    for (final box in _children(data, mdia.start, mdia.end)) {
      switch (box.type) {
        case 'mdhd':
          final version = data[box.start];
          if (version == 1 && box.start + 32 <= box.end) {
            track.timescale = view.getUint32(box.start + 20);
            track.durationUnits = view.getUint64(box.start + 24);
          } else if (box.start + 20 <= box.end) {
            track.timescale = view.getUint32(box.start + 12);
            track.durationUnits = view.getUint32(box.start + 16);
          }
        case 'hdlr':
          if (box.start + 12 <= box.end) track.handler = latin1.decode(data.sublist(box.start + 8, box.start + 12));
        case 'minf':
          for (final stbl in _children(data, box.start, box.end)) {
            if (stbl.type == 'stbl') _parseSampleTable(stbl, track);
          }
      }
    }
  }

  void _parseSampleTable(_Box stbl, _Track track) {
    for (final box in _children(data, stbl.start, stbl.end)) {
      final count = box.start + 8 <= box.end ? view.getUint32(box.start + 4) : 0;
      switch (box.type) {
        case 'stts':
          track.timeToSample = [
            for (var i = 0, p = box.start + 8; i < count && p + 8 <= box.end; i++, p += 8)
              (view.getUint32(p), view.getUint32(p + 4)),
          ];
        case 'stsc':
          track.sampleToChunk = [
            for (var i = 0, p = box.start + 8; i < count && p + 12 <= box.end; i++, p += 12)
              (view.getUint32(p), view.getUint32(p + 4)),
          ];
        case 'stsz':
          if (box.start + 12 > box.end) break;
          track.uniformSampleSize = view.getUint32(box.start + 4);
          track.sampleCount = view.getUint32(box.start + 8);
          if (track.uniformSampleSize == 0) {
            track.sampleSizes = [
              for (var i = 0, p = box.start + 12; i < track.sampleCount && p + 4 <= box.end; i++, p += 4)
                view.getUint32(p),
            ];
          }
        case 'stco':
          track.chunkOffsets = [
            for (var i = 0, p = box.start + 8; i < count && p + 4 <= box.end; i++, p += 4) view.getUint32(p),
          ];
        case 'co64':
          track.chunkOffsets = [
            for (var i = 0, p = box.start + 8; i < count && p + 8 <= box.end; i++, p += 8) view.getUint64(p),
          ];
      }
    }
  }
}

List<TagChapter> _readQuickTimeChapters(RandomAccessFile file, List<_Track> tracks) {
  final audio = tracks.where((t) => t.handler == 'soun' && t.chapterTrackIds.isNotEmpty).firstOrNull;
  if (audio == null) return const [];
  final chapterTrack = tracks.where((t) => audio.chapterTrackIds.contains(t.id) && t.id != audio.id).firstOrNull;
  if (chapterTrack == null || chapterTrack.timescale <= 0) return const [];

  final sampleCount = chapterTrack.sampleCount.clamp(0, _maxChapters);
  if (sampleCount == 0) return const [];
  int sizeOf(int i) => chapterTrack.uniformSampleSize != 0
      ? chapterTrack.uniformSampleSize
      : (i < chapterTrack.sampleSizes.length ? chapterTrack.sampleSizes[i] : 0);

  // Start time of every sample.
  final starts = <int>[];
  var time = 0;
  for (final (count, delta) in chapterTrack.timeToSample) {
    for (var i = 0; i < count && starts.length < sampleCount; i++) {
      starts.add(time);
      time += delta;
    }
  }

  // File offset of every sample, from the sample-to-chunk runs.
  final offsets = <int>[];
  final runs = chapterTrack.sampleToChunk;
  final chunks = chapterTrack.chunkOffsets;
  for (var r = 0; r < runs.length && offsets.length < sampleCount; r++) {
    final (firstChunk, perChunk) = runs[r];
    final lastChunk = r + 1 < runs.length ? runs[r + 1].$1 - 1 : chunks.length;
    for (var chunk = firstChunk; chunk <= lastChunk && chunk - 1 < chunks.length; chunk++) {
      var offset = chunks[chunk - 1];
      for (var s = 0; s < perChunk && offsets.length < sampleCount; s++) {
        offsets.add(offset);
        offset += sizeOf(offsets.length - 1);
      }
    }
  }

  final count = [starts.length, offsets.length, sampleCount].reduce((a, b) => a < b ? a : b);
  final length = file.lengthSync();
  final chapters = <TagChapter>[];
  for (var i = 0; i < count; i++) {
    final size = sizeOf(i);
    String? title;
    if (size >= 2 && offsets[i] + size <= length) {
      file.setPositionSync(offsets[i]);
      final sample = file.readSync(size > 4096 ? 4096 : size);
      if (sample.length >= 2) {
        final textLength = (sample[0] << 8) | sample[1];
        final end = 2 + textLength > sample.length ? sample.length : 2 + textLength;
        title = cleanTag(_decodeText(sample.sublist(2, end)));
      }
    }
    final start = Duration(microseconds: starts[i] * 1000000 ~/ chapterTrack.timescale);
    chapters.add(TagChapter(start: start, title: title));
  }
  return chapters;
}

String _decodeText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), bigEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), bigEndian: false);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeUtf16(Uint8List bytes, {required bool bigEndian}) {
  final units = <int>[
    for (var i = 0; i + 1 < bytes.length; i += 2)
      bigEndian ? (bytes[i] << 8) | bytes[i + 1] : (bytes[i + 1] << 8) | bytes[i],
  ];
  return String.fromCharCodes(units);
}
