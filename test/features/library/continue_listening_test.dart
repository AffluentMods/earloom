// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/library/data/continue_listening.dart';
import 'package:flutter_test/flutter_test.dart';

BookSummary onPhone(String id, {DateTime? played}) => BookSummary(
  ref: ItemRef(const LocalSource(), id),
  title: id,
  isDownloaded: true,
  progress: played == null
      ? null
      : ListeningProgress(
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
          updatedAt: played,
        ),
);

void main() {
  final takenOut = DateTime(2026, 11, 24, 21);

  test('a book on this phone stays out until it is played again', () {
    final hidden = {'atlas': takenOut};
    expect(isHiddenLocally(onPhone('atlas', played: DateTime(2026, 11, 24, 20)), hidden), isTrue);
    expect(isHiddenLocally(onPhone('atlas', played: takenOut), hidden), isTrue);
    expect(isHiddenLocally(onPhone('atlas', played: DateTime(2026, 11, 24, 22)), hidden), isFalse);
    expect(isHiddenLocally(onPhone('other', played: DateTime(2026, 11, 24, 20)), hidden), isFalse);
  });

  test('the saved list reads back, skipping anything it does not know', () {
    final read = decodeHiddenLocalBooks('{"atlas": ${takenOut.millisecondsSinceEpoch}, "junk": "x", "n": null}');
    expect(read, {'atlas': takenOut});
    expect(decodeHiddenLocalBooks('[1, 2]'), isEmpty);
    expect(decodeHiddenLocalBooks('not json'), isEmpty);
    expect(decodeHiddenLocalBooks(null), isEmpty);
  });
}
