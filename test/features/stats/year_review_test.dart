// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/stats/data/stats_repository.dart';
import 'package:earloom/features/stats/data/year_review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';

HourBucket _b(DateTime day, int hour, int minutes, String ref, {double speed = 1}) => HourBucket(
  day: day,
  hour: hour,
  refKey: ref,
  seconds: minutes * 60.0,
  bookSeconds: minutes * 60.0 * speed,
);

final _input = StatsInput(
  buckets: [
    _b(DateTime(2025, 12, 30), 21, 300, 'a'),
    _b(DateTime(2026, 3, 1), 21, 60, 'a', speed: 1.5),
    _b(DateTime(2026, 3, 2), 21, 60, 'a', speed: 1.5),
    _b(DateTime(2026, 3, 3), 7, 30, 'b', speed: 1.5),
    _b(DateTime(2026, 7, 4), 21, 45, 'b', speed: 1.5),
  ],
  sessionSeconds: const [],
  books: {
    'a': StatsBook(
      refKey: 'a',
      title: 'Salt and Starlight',
      author: 'Mara Ellison',
      narrator: 'Jonah Pryce',
      finishedAt: DateTime(2026, 3, 2),
    ),
    'b': StatsBook(refKey: 'b', title: 'Kindling Sky', author: 'Theo Vance', finishedAt: DateTime(2025, 6, 1)),
  },
);

void main() {
  setUpAll(loadAppFonts);

  test('a year review counts only that year', () {
    final r = computeYearReview(_input, 2026);
    expect(r.time, const Duration(minutes: 195));
    expect(r.bookTime.inMinutes, closeTo(292, 1));
    expect(r.finished.map((b) => b.title), ['Salt and Starlight']);
    expect(r.topAuthor?.name, 'Mara Ellison');
    expect(r.longestStreak, 3);
    expect(r.busiestMonth, 3);
    expect(r.favoriteHour, 21);
    expect(computeYearReview(_input, 2024).isEmpty, isTrue);
  });

  test('the review is in season from December to January', () {
    expect(reviewYearInSeason(DateTime(2026, 12, 1)), 2026);
    expect(reviewYearInSeason(DateTime(2027, 1, 31)), 2026);
    expect(reviewYearInSeason(DateTime(2026, 11, 14)), isNull);
  });

  testWidgets('the cards show and can be swiped', (tester) async {
    usePhoneSize(tester);
    final l10n = await loadL10n();
    await pumpEarloom(
      tester,
      initialRoute: '/you/stats/year/2026',
      overrides: [yearReviewProvider(2026).overrideWithValue(AsyncData(computeYearReview(_input, 2026)))],
    );
    await settle(tester);
    expect(find.text(l10n.yearReviewHoursLead), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await settle(tester);
    expect(find.text(l10n.yearReviewBooks(1)), findsOneWidget);
    expect(find.text(l10n.yearReviewShare), findsOneWidget);
  });
}
