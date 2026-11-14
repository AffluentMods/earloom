// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/util/timestamps.dart';
import 'package:flutter_test/flutter_test.dart';

List<Duration> times(String text, {Duration? max}) => [
  for (final p in splitTimestamps(text, maxPosition: max))
    if (p.at != null) p.at!,
];

void main() {
  test('minutes and seconds, hours too', () {
    expect(times('Intro at 0:45, the interview at 12:34, outro 1:02:03.'), [
      const Duration(seconds: 45),
      const Duration(minutes: 12, seconds: 34),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    ]);
  });

  test('long episodes write minutes past 60', () {
    expect(times('Bonus at 75:10'), [const Duration(minutes: 75, seconds: 10)]);
  });

  test('keeps every character, in order', () {
    const text = '(00:30) Cold open; 2:30 - news';
    final pieces = splitTimestamps(text);
    expect(pieces.map((p) => p.text).join(), text);
    expect(pieces, [
      const TextPiece('('),
      const TextPiece('00:30', Duration(seconds: 30)),
      const TextPiece(') Cold open; '),
      const TextPiece('2:30', Duration(minutes: 2, seconds: 30)),
      const TextPiece(' - news'),
    ]);
  });

  test('not a timestamp: bad seconds, times of day, ratios, versions, longer runs', () {
    expect(times('12:61 and 1:75:00'), isEmpty);
    expect(times('Live at 10:30 pm, doors 9:15am, 7:00 P.M.'), isEmpty);
    expect(times('Score 1:2, version 2.10:30, 1:02:03:04'), isEmpty);
    expect(times('Price 3,12:30'), isEmpty);
  });

  test('times past the end of the episode stay plain text', () {
    expect(times('At 4:00 and 9:00', max: const Duration(minutes: 5)), [const Duration(minutes: 4)]);
    expect(times('At 4:00 and 9:00', max: Duration.zero), hasLength(2), reason: 'unknown length: keep all');
  });

  test('text without times is one plain piece', () {
    expect(splitTimestamps('No times here.'), [const TextPiece('No times here.')]);
    expect(splitTimestamps(''), isEmpty);
  });
}
