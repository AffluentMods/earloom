// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';
import 'dart:typed_data';

/// Duration of an MP3 stream from its headers: the Xing, Info or VBRI frame
/// count when there is one, the constant bitrate otherwise.
///
/// `audio_metadata_reader` only looks for "Xing" (not the "Info" header LAME
/// writes into constant bitrate files) and estimates from the wrong numbers,
/// so its MP3 durations can be far off.
Duration? readMp3Duration(RandomAccessFile file, {int audioStart = 0}) {
  try {
    final length = file.lengthSync();
    file.setPositionSync(audioStart);
    final window = file.readSync(256 * 1024);
    for (var i = 0; i + 4 <= window.length; i++) {
      final frame = _MpegFrame.tryParse(window, i);
      if (frame == null) continue;
      // A real frame is followed by another one. This skips false syncs in
      // leftover tag data.
      final next = i + frame.length;
      if (next + 4 <= window.length && _MpegFrame.tryParse(window, next) == null) continue;

      final xing = i + 4 + frame.sideInfoLength;
      if (xing + 12 <= window.length && (_ascii(window, xing, 'Xing') || _ascii(window, xing, 'Info'))) {
        final flags = _uint32(window, xing + 4);
        if ((flags & 0x1) != 0) {
          return _fromSamples(_uint32(window, xing + 8) * frame.samplesPerFrame, frame.sampleRate);
        }
      }
      final vbri = i + 4 + 32;
      if (vbri + 18 <= window.length && _ascii(window, vbri, 'VBRI')) {
        return _fromSamples(_uint32(window, vbri + 14) * frame.samplesPerFrame, frame.sampleRate);
      }
      var audioBytes = length - (audioStart + i);
      if (_hasId3v1(file, length)) audioBytes -= 128;
      if (frame.bitrate <= 0 || audioBytes <= 0) return null;
      return Duration(microseconds: audioBytes * 8 * 1000000 ~/ frame.bitrate);
    }
    return null;
  } on Object {
    return null;
  }
}

/// Duration of a raw AAC (ADTS) stream, by walking every frame header. Raw
/// AAC has no index, so this is the only way to know.
Duration? readAdtsDuration(RandomAccessFile file, {int audioStart = 0}) {
  try {
    final length = file.lengthSync();
    var pos = audioStart;
    var samples = 0;
    var sampleRate = 0;
    var misses = 0;
    while (pos + 7 <= length) {
      file.setPositionSync(pos);
      final block = file.readSync(1024 * 1024);
      var i = 0;
      while (i + 7 <= block.length) {
        final b1 = block[i + 1];
        if (block[i] != 0xFF || (b1 & 0xF6) != 0xF0) {
          i++;
          if (++misses > 64 * 1024) return null;
          continue;
        }
        final rateIndex = (block[i + 2] >> 2) & 0x0F;
        final frameLength = ((block[i + 3] & 0x03) << 11) | (block[i + 4] << 3) | (block[i + 5] >> 5);
        if (rateIndex >= _adtsRates.length || frameLength < 7) {
          i++;
          continue;
        }
        if (i + frameLength > block.length && pos + i + frameLength <= length) break; // read on
        sampleRate = _adtsRates[rateIndex];
        samples += 1024 * ((block[i + 6] & 0x03) + 1);
        i += frameLength;
      }
      if (i == 0) break;
      pos += i;
    }
    if (sampleRate == 0) return null;
    return _fromSamples(samples, sampleRate);
  } on Object {
    return null;
  }
}

const _adtsRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

Duration? _fromSamples(int samples, int sampleRate) {
  if (sampleRate <= 0 || samples <= 0) return null;
  return Duration(microseconds: samples * 1000000 ~/ sampleRate);
}

bool _hasId3v1(RandomAccessFile file, int length) {
  if (length < 128) return false;
  file.setPositionSync(length - 128);
  final tag = file.readSync(3);
  return tag.length == 3 && tag[0] == 0x54 && tag[1] == 0x41 && tag[2] == 0x47;
}

bool _ascii(Uint8List bytes, int pos, String text) {
  for (var i = 0; i < text.length; i++) {
    if (bytes[pos + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

int _uint32(Uint8List b, int pos) => (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];

/// One MPEG audio frame header.
final class _MpegFrame {
  const _MpegFrame({
    required this.bitrate,
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.length,
    required this.sideInfoLength,
  });

  /// Bits per second.
  final int bitrate;
  final int sampleRate;
  final int samplesPerFrame;

  /// Frame length in bytes, header included.
  final int length;

  /// Bytes between the header and a Xing/Info tag (Layer III side info).
  final int sideInfoLength;

  static _MpegFrame? tryParse(Uint8List b, int i) {
    if (i + 4 > b.length || b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) return null;
    final versionBits = (b[i + 1] >> 3) & 0x03; // 0: 2.5, 2: 2, 3: 1
    final layerBits = (b[i + 1] >> 1) & 0x03; // 1: III, 2: II, 3: I
    final bitrateIndex = b[i + 2] >> 4;
    final rateIndex = (b[i + 2] >> 2) & 0x03;
    final padding = (b[i + 2] >> 1) & 0x01;
    final mono = (b[i + 3] >> 6) == 0x03;
    if (versionBits == 1 || layerBits == 0 || bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) {
      return null;
    }
    final mpeg1 = versionBits == 3;
    final layer = 4 - layerBits;
    final kbps = mpeg1
        ? const [_v1l1, _v1l2, _v1l3][layer - 1][bitrateIndex]
        : (layer == 1 ? _v2l1 : _v2l23)[bitrateIndex];
    final sampleRate = const [
      [11025, 12000, 8000],
      [0, 0, 0],
      [22050, 24000, 16000],
      [44100, 48000, 32000],
    ][versionBits][rateIndex];
    final samplesPerFrame = layer == 1 ? 384 : (layer == 2 || mpeg1 ? 1152 : 576);
    final bitrate = kbps * 1000;
    final length = layer == 1
        ? (12 * bitrate ~/ sampleRate + padding) * 4
        : samplesPerFrame ~/ 8 * bitrate ~/ sampleRate + padding;
    if (length < 4) return null;
    final sideInfo = layer != 3 ? 0 : (mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17));
    return _MpegFrame(
      bitrate: bitrate,
      sampleRate: sampleRate,
      samplesPerFrame: samplesPerFrame,
      length: length,
      sideInfoLength: sideInfo,
    );
  }
}

const _v1l1 = [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448];
const _v1l2 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384];
const _v1l3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const _v2l1 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256];
const _v2l23 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
