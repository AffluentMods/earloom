// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// A piece of show notes text: plain, or a timestamp ("12:34", "1:02:03")
/// that points into the episode.
final class TextPiece {
  const TextPiece(this.text, [this.at]);

  final String text;

  /// The position the timestamp names, or null for plain text.
  final Duration? at;

  bool get isTimestamp => at != null;

  @override
  bool operator ==(Object other) => other is TextPiece && other.text == text && other.at == at;

  @override
  int get hashCode => Object.hash(text, at);

  @override
  String toString() => at == null ? 'TextPiece($text)' : 'TextPiece($text @ $at)';
}

// h:mm:ss or m:ss / mm:ss (minutes up to three digits), not part of a
// longer run of digits and colons, and not a time of day ("10:30 pm").
final _timestamp = RegExp(
  r'(?<![\d:.,])(?:(\d{1,2}):([0-5]\d):([0-5]\d)|(\d{1,3}):([0-5]\d))(?![\d:]|[.,]\d)(?!\s?[aApP]\.?[mM]\b)',
);

/// Splits [text] into plain pieces and timestamps. A timestamp past
/// [maxPosition] (the episode's length, when known) stays plain text: it
/// cannot be a place in this episode.
List<TextPiece> splitTimestamps(String text, {Duration? maxPosition}) {
  final pieces = <TextPiece>[];
  var last = 0;
  for (final m in _timestamp.allMatches(text)) {
    final Duration at;
    if (m.group(1) != null) {
      at = Duration(
        hours: int.parse(m.group(1)!),
        minutes: int.parse(m.group(2)!),
        seconds: int.parse(m.group(3)!),
      );
    } else {
      at = Duration(minutes: int.parse(m.group(4)!), seconds: int.parse(m.group(5)!));
    }
    if (maxPosition != null && maxPosition > Duration.zero && at > maxPosition) continue;
    if (m.start > last) pieces.add(TextPiece(text.substring(last, m.start)));
    pieces.add(TextPiece(m.group(0)!, at));
    last = m.end;
  }
  if (last < text.length) pieces.add(TextPiece(text.substring(last)));
  return pieces;
}
