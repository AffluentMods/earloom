// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/stats/data/stats_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';

void main() {
  setUpAll(loadAppFonts);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sample = computeStats(
    StatsInput(
      buckets: [
        for (var i = 0; i < 9; i++)
          HourBucket(
            day: DateTime(today.year, today.month, today.day - i),
            hour: 21,
            refKey: 'local|b${i % 3}',
            seconds: (20 + i * 4) * 60.0,
            bookSeconds: (26 + i * 5) * 60.0,
          ),
      ],
      sessionSeconds: const [3000, 1200],
      books: {
        for (var i = 0; i < 3; i++)
          'local|b$i': StatsBook(
            refKey: 'local|b$i',
            title: ['Salt and Starlight', "The Clockmaker's Tide", 'The Long Way to Morning'][i],
            author: ['Mara Ellison', 'Mara Ellison', 'Rafael Dorn'][i],
            narrator: 'Jonah Pryce',
            finishedAt: i == 0 ? today : null,
          ),
      },
    ),
    now: now,
  );

  testWidgets('the stats screen shows today, the week, totals and favorites', (tester) async {
    tester.view.physicalSize = const Size(390, 3200) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final l10n = await loadL10n();
    await pumpEarloom(
      tester,
      initialRoute: '/you/stats',
      overrides: [
        statsProvider.overrideWithValue(AsyncData(sample)),
        serverStatsProvider.overrideWithValue(const AsyncData(StatsInput.empty)),
      ],
    );
    await settle(tester);
    expect(find.text(l10n.statsTitle), findsWidgets);
    expect(find.text(l10n.statsStreak(9)), findsOneWidget);
    expect(find.text(l10n.statsThisWeek), findsOneWidget);
    expect(find.text(l10n.statsTopAuthors), findsOneWidget);
    expect(find.text('Mara Ellison'), findsWidgets);
    expect(find.text(l10n.statsFinishedIn(now.year)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no listening shows a friendly empty state', (tester) async {
    final l10n = await loadL10n();
    await pumpEarloom(
      tester,
      initialRoute: '/you/stats',
      overrides: [
        statsProvider.overrideWithValue(AsyncData(computeStats(StatsInput.empty, now: now))),
        serverStatsProvider.overrideWithValue(const AsyncData(StatsInput.empty)),
      ],
    );
    await settle(tester);
    expect(find.text(l10n.statsEmptyTitle), findsOneWidget);
  });
}
