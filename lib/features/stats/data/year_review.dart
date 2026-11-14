// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stats_repository.dart';

/// One year of listening, for the shareable story cards
/// (docs/plan/08-phase7-stats.md 7.4).
final class YearReview {
  const YearReview({
    required this.year,
    required this.time,
    required this.bookTime,
    required this.finished,
    required this.longestStreak,
    this.topAuthor,
    this.topNarrator,
    this.busiestMonth,
    this.favoriteHour,
  });

  final int year;
  final Duration time;
  final Duration bookTime;
  final List<StatsBook> finished;
  final int longestStreak;
  final Ranked? topAuthor;
  final Ranked? topNarrator;

  /// 1 to 12.
  final int? busiestMonth;

  /// 0 to 23.
  final int? favoriteHour;

  bool get isEmpty => time == Duration.zero;
}

/// The review of [year] from all stats input.
YearReview computeYearReview(StatsInput input, int year) {
  final inYear = StatsInput(
    buckets: [
      for (final b in input.buckets)
        if (b.day.year == year) b,
    ],
    sessionSeconds: input.sessionSeconds,
    books: {
      for (final e in input.books.entries)
        e.key: StatsBook(
          refKey: e.value.refKey,
          title: e.value.title,
          author: e.value.author,
          narrator: e.value.narrator,
          cover: e.value.cover,
          finishedAt: e.value.finishedAt?.toLocal().year == year ? e.value.finishedAt : null,
        ),
    },
  );
  // "Now" at the end of the year, so "this year" means that year.
  final stats = computeStats(inYear, now: DateTime(year, 12, 31, 23, 59));
  final months = List<double>.filled(12, 0);
  for (final b in inYear.buckets) {
    months[b.day.month - 1] += b.seconds;
  }
  int? peak(List<num> values) {
    var best = -1;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > 0 && (best < 0 || values[i] > values[best])) best = i;
    }
    return best < 0 ? null : best;
  }

  final month = peak(months);
  return YearReview(
    year: year,
    time: stats.total,
    bookTime: stats.bookTime,
    finished: stats.finishedThisYear,
    longestStreak: stats.longestStreak,
    topAuthor: stats.topAuthors.firstOrNull,
    topNarrator: stats.topNarrators.firstOrNull,
    busiestMonth: month == null ? null : month + 1,
    favoriteHour: peak([for (final h in stats.hours) h.inSeconds]),
  );
}

/// Whether the review of the year just ending is in season: December 1
/// through January 31.
int? reviewYearInSeason(DateTime now) => switch (now.month) {
  12 => now.year,
  1 => now.year - 1,
  _ => null,
};

final yearReviewProvider = FutureProvider.autoDispose.family<YearReview, int>((ref, year) async {
  final log = ref.watch(listeningLogProvider);
  final server = await ref.watch(serverStatsProvider.future).catchError((Object _) => StatsInput.empty);
  return computeYearReview(mergeInputs(await localStatsInput(log), server), year);
});
