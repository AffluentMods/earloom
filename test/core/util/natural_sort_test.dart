// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/util/natural_sort.dart';
import 'package:earloom/core/util/search_fold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareNatural', () {
    List<String> sorted(List<String> values) => [...values]..sort(compareNatural);

    test('numbers compare by value', () {
      expect(sorted(['10.mp3', '2.mp3', '1.mp3']), ['1.mp3', '2.mp3', '10.mp3']);
      expect(sorted(['Track 10', 'Track 9', 'Track 100']), ['Track 9', 'Track 10', 'Track 100']);
    });

    test('ignores case, keeps a total order', () {
      expect(sorted(['b', 'A', 'a', 'B']), ['A', 'a', 'B', 'b']);
    });

    test('leading zeros: same value, fewer zeros first', () {
      expect(sorted(['007', '7', '07']), ['7', '07', '007']);
      expect(compareNatural('01 Intro', '1 Intro'), greaterThan(0));
    });

    test('prefixes sort before longer names', () {
      expect(sorted(['Part 1b', 'Part 1', 'Part']), ['Part', 'Part 1', 'Part 1b']);
    });

    test('very long digit runs do not overflow', () {
      expect(compareNatural('99999999999999999999999', '100000000000000000000000'), lessThan(0));
    });
  });

  test('padNumbers makes a plain sort natural', () {
    final values = ['Book 10', 'Book 2', 'Book 1'].map(padNumbers).toList()..sort();
    expect(values, [padNumbers('Book 1'), padNumbers('Book 2'), padNumbers('Book 10')]);
    expect(padNumbers('Vol 007'), 'Vol 0000000007');
  });

  test('foldForSearch drops case, accents and extra spaces', () {
    expect(foldForSearch('  Émile   ZOLA '), 'emile zola');
    expect(foldForSearch('Straße'), 'strasse');
    expect(foldForSearch('Łódź'), 'lodz');
  });
}
