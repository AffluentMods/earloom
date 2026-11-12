# Phase 7: Listening stats

Goal: stats people actually look at and share. Accurate (no double counting between offline and online), fast, and pretty.

Branch: `phase-7-stats`

---

## 7.1 Data sources and model

- Server: listening stats and listening sessions endpoints (shapes in `docs/abs-api.md`).
- Local: `local_sessions` not yet synced (Phase 4). Merge by session id so a session is never counted twice.
- Derived local tables (AccountDb), rebuilt on demand:

| Table | Columns |
|---|---|
| `stats_days` | date (local yyyy-mm-dd), seconds, sessions |
| `stats_sessions` | id, itemId, episodeId, startedAt, endedAt, seconds, mediaSeconds (position delta, reflects speed) |

Rules:
- Day buckets use the device's local timezone from session timestamps. If the server only offers pre-bucketed days, check what timezone it used and document it in `docs/abs-api.md`.
- Real time listened (wall clock) is the headline number. Content time (book minutes covered, larger at high speed) is a secondary stat.
- Refresh on opening the stats screen if older than 10 minutes, and after the outbox flushes local sessions.

### Acceptance
- [ ] Offline listening, then sync: totals equal the sum of real listening, verified against ABS
- [ ] Session spanning midnight splits correctly across two days

---

## 7.2 Stats screen (You > Stats)

Files: `lib/features/stats/ui/stats_screen.dart`, `lib/features/stats/ui/widgets/*.dart`

Sections:
1. **Today**: ring toward the daily goal (default 30 min, configurable), minutes today, current streak.
2. **This week**: bar chart per day, average per day, change vs last week.
3. **Calendar**: month heatmap, swipe between months, tap a day for that day's sessions.
4. **Totals**: all-time hours, books finished, podcast episodes finished, longest session, longest streak.
5. **Speed dividend**: "You heard 120 hr of books in 92 hr" (content time vs real time).
6. **Top lists**: top authors, narrators and genres by listening time, with covers or author photos.
7. **When you listen**: hour-of-day histogram, weekday split.
8. **Finished this year**: cover grid of books finished, sorted by finish date.

Streak definition: consecutive local days with at least 5 minutes listened. Goal and streak threshold are settings.

Charts: `fl_chart` (or custom painters if lighter). Colors from theme tokens and the scheme, never hardcoded. Every chart has a text alternative for screen readers ("Monday 42 minutes, Tuesday 0 minutes...").

### Acceptance
- [ ] Stats screen opens from cache in under 300ms
- [ ] Numbers match the ABS web UI stats page for the same account
- [ ] Charts readable at 200% text size

---

## 7.3 Per-book stats

On item detail, a small "Your listening" block: time spent, number of sessions, started on, finished on, average speed. Hidden for items never played.

---

## 7.4 Year in review

File: `lib/features/stats/ui/year_review.dart`

- Available from December 1 through January 31 for the year just ending, plus on demand for any past year with data.
- Swipeable story cards (9:16): total hours, books finished (cover collage), top author, top narrator, longest streak, busiest month, favorite listening hour, speed dividend.
- Share: render a card with `RepaintBoundary` to PNG, share via `share_plus`. Square and story formats. Only the rendered image leaves the device, and only when the user shares.
- Cover colors drive the card palette.

### Acceptance
- [ ] Shared image looks right in light and dark mode and contains no server URL or username
- [ ] Generates in under 2s for a year with 100 finished books

---

## l10n keys added in Phase 7

```
statsTitle, statsToday, statsGoal(minutes), statsMinutesToday(minutes), statsStreak(days), statsThisWeek,
statsAvgPerDay(duration), statsVsLastWeek(percent), statsCalendar, statsTotals, statsAllTimeHours(hours),
statsBooksFinished(count), statsEpisodesFinished(count), statsLongestSession(duration), statsLongestStreak(days),
statsSpeedDividend(contentTime, realTime), statsTopAuthors, statsTopNarrators, statsTopGenres,
statsWhenYouListen, statsFinishedThisYear(year), statsDaySessions(date), statsChartDayA11y(day, minutes),
itemYourListening, itemTimeSpent(duration), itemSessions(count), itemStartedOn(date), itemFinishedOn(date),
itemAvgSpeed(speed), yearReviewTitle(year), yearReviewHours(hours), yearReviewBooks(count), yearReviewTopAuthor(name),
yearReviewTopNarrator(name), yearReviewStreak(days), yearReviewBusiestMonth(month), yearReviewFavoriteHour(hour),
yearReviewShare, yearReviewFormatStory, yearReviewFormatSquare,
settingsDailyGoal, settingsStreakThreshold
```

## Phase 7 done when
- [ ] All section checklists ticked
- [ ] Golden tests for each stats section and each year-in-review card
