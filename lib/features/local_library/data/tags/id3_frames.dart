// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'file_tags.dart';

/// What we read from an ID3v2 tag ourselves: where the audio starts and the
/// `CHAP` chapter frames. `audio_metadata_reader` keeps only one unknown
/// frame per id, so it loses all chapters but the last.
final class Id3Info {
  const Id3Info({this.tagLength = 0, this.chapters = const []});

  /// Bytes taken by the ID3v2 tag at the start of the file (0 when none).
  final int tagLength;
  final List<TagChapter> chapters;
}

const _maxTagBytes = 64 * 1024 * 1024;
final _frameId = RegExp(r'^[A-Z0-9]{4}$');

/// Reads [Id3Info] from the start of [file]. Never throws on malformed input.
Id3Info readId3Info(RandomAccessFile file) {
  try {
    file.setPositionSync(0);
    final header = file.readSync(10);
    if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return const Id3Info();
    }
    final major = header[3];
    final flags = header[5];
    final size = _syncSafe(header, 6);
    final footer = major == 4 && (flags & 0x10) != 0 ? 10 : 0;
    final tagLength = 10 + size + footer;
    // ID3v2.2 has three letter frame ids and no chapters.
    if (major < 3 || major > 4 || size > _maxTagBytes) return Id3Info(tagLength: tagLength);

    var body = file.readSync(size);
    if (major == 3 && (flags & 0x80) != 0) body = _removeUnsync(body);
    var pos = 0;
    if ((flags & 0x40) != 0 && body.length >= 4) {
      // Extended header: its size excludes itself in 2.3, includes it in 2.4.
      pos = major == 3 ? 4 + _uint32(body, 0) : _syncSafe(body, 0);
    }
    final chapters = <TagChapter>[];
    _forEachFrame(body, pos, body.length, major, (id, data) {
      if (id == 'CHAP') {
        final chapter = _parseChap(data, major);
        if (chapter != null) chapters.add(chapter);
      }
    });
    chapters.sort((a, b) => a.start.compareTo(b.start));
    return Id3Info(tagLength: tagLength, chapters: chapters);
  } on Object {
    return const Id3Info();
  }
}

void _forEachFrame(Uint8List bytes, int start, int end, int major, void Function(String id, Uint8List data) onFrame) {
  var pos = start;
  while (pos + 10 <= end) {
    if (bytes[pos] == 0) return; // padding
    final id = latin1.decode(bytes.sublist(pos, pos + 4));
    if (!_frameId.hasMatch(id)) return;
    final size = major == 4 ? _syncSafe(bytes, pos + 4) : _uint32(bytes, pos + 4);
    final formatFlags = bytes[pos + 9];
    final dataStart = pos + 10;
    final dataEnd = dataStart + size;
    if (size < 0 || dataEnd > end) return;
    var data = bytes.sublist(dataStart, dataEnd);
    var usable = true;
    if (major == 4) {
      if ((formatFlags & 0x0C) != 0) usable = false; // compressed or encrypted
      if ((formatFlags & 0x01) != 0 && data.length >= 4) data = data.sublist(4); // data length indicator
      if ((formatFlags & 0x02) != 0) data = _removeUnsync(data);
    } else {
      if ((formatFlags & 0xC0) != 0) usable = false; // compressed or encrypted
      if ((formatFlags & 0x20) != 0 && data.isNotEmpty) data = data.sublist(1); // group id
    }
    if (usable) onFrame(id, data);
    pos = dataEnd;
  }
}

TagChapter? _parseChap(Uint8List data, int major) {
  final idEnd = data.indexOf(0);
  if (idEnd < 0 || idEnd + 17 > data.length) return null;
  final startMs = _uint32(data, idEnd + 1);
  final endMs = _uint32(data, idEnd + 5);
  String? title;
  _forEachFrame(data, idEnd + 17, data.length, major, (id, sub) {
    if (id == 'TIT2') title ??= cleanTag(decodeId3Text(sub));
  });
  return TagChapter(
    start: Duration(milliseconds: startMs),
    end: endMs == 0xFFFFFFFF || endMs <= startMs ? null : Duration(milliseconds: endMs),
    title: title,
  );
}

/// Decodes an ID3 text frame: one encoding byte, then the text.
String decodeId3Text(Uint8List data) {
  if (data.isEmpty) return '';
  final text = data.sublist(1);
  final String decoded;
  switch (data[0]) {
    case 1:
      if (text.length >= 2 && text[0] == 0xFE && text[1] == 0xFF) {
        decoded = _utf16(text.sublist(2), bigEndian: true);
      } else if (text.length >= 2 && text[0] == 0xFF && text[1] == 0xFE) {
        decoded = _utf16(text.sublist(2), bigEndian: false);
      } else {
        decoded = _utf16(text, bigEndian: false);
      }
    case 2:
      decoded = _utf16(text, bigEndian: true);
    case 3:
      decoded = utf8.decode(text, allowMalformed: true);
    default:
      decoded = latin1.decode(text);
  }
  final nul = decoded.indexOf('\u0000');
  return nul < 0 ? decoded : decoded.substring(0, nul);
}

String _utf16(Uint8List bytes, {required bool bigEndian}) {
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2)
      bigEndian ? (bytes[i] << 8) | bytes[i + 1] : (bytes[i + 1] << 8) | bytes[i],
  ]);
}

Uint8List _removeUnsync(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    out.addByte(bytes[i]);
    if (bytes[i] == 0xFF && i + 1 < bytes.length && bytes[i + 1] == 0x00) i++;
  }
  return out.takeBytes();
}

int _syncSafe(List<int> b, int pos) =>
    ((b[pos] & 0x7F) << 21) | ((b[pos + 1] & 0x7F) << 14) | ((b[pos + 2] & 0x7F) << 7) | (b[pos + 3] & 0x7F);

int _uint32(List<int> b, int pos) => (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
