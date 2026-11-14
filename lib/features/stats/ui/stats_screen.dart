// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../app/router.dart';
import '../data/stats_repository.dart';
import '../data/year_review.dart';

/// You > Listening stats.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = ref.watch(statsProvider);
    final serverFailed = ref.watch(serverStatsProvider).hasError;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(serverStatsProvider.future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(l10n.statsTitle),
              actions: [
                IconButton(
                  tooltip: l10n.yearReviewOpen,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () =>
                      context.push(AppRoutes.yearReview(reviewYearInSeason(DateTime.now()) ?? DateTime.now().year)),
                ),
              ],
            ),
            switch (stats) {
              AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.insights_rounded,
                  title: l10n.statsEmptyTitle,
                  body: l10n.statsEmptyBody,
                ),
              ),
              AsyncData(:final value) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
                sliver: SliverList.list(
                  children: [
                    if (serverFailed) ...[
                      InlineNotice(icon: Icons.cloud_off_rounded, message: l10n.statsServerFailed),
                      const SizedBox(height: Space.lg),
                    ],
                    if (reviewYearInSeason(DateTime.now()) case final year?) ...[
                      _YearReviewBanner(year: year),
                      const SizedBox(height: Space.lg),
                    ],
                    _TodayCard(stats: value),
                    const SizedBox(height: Space.xl),
                    _WeekSection(stats: value),
                    const SizedBox(height: Space.xl),
                    _CalendarSection(stats: value),
                    const SizedBox(height: Space.xl),
                    _TotalsSection(stats: value),
                    if (value.topBooks.isNotEmpty) ...[
                      const SizedBox(height: Space.xl),
                      _TopBooks(stats: value),
                    ],
                    if (value.topAuthors.isNotEmpty) ...[
                      const SizedBox(height: Space.xl),
                      _RankedList(title: l10n.statsTopAuthors, entries: value.topAuthors),
                    ],
                    if (value.topNarrators.isNotEmpty) ...[
                      const SizedBox(height: Space.xl),
                      _RankedList(title: l10n.statsTopNarrators, entries: value.topNarrators),
                    ],
                    const SizedBox(height: Space.xl),
                    _WhenSection(stats: value),
                    if (value.finishedThisYear.isNotEmpty) ...[
                      const SizedBox(height: Space.xl),
                      _FinishedSection(stats: value),
                    ],
                  ],
                ),
              ),
              AsyncError(:final error) => SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: ErrorNotice(message: l10n.genericSomethingWentWrong, details: '$error'),
                ),
              ),
              _ => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            },
          ],
        ),
      ),
    );
  }
}

class _YearReviewBanner extends StatelessWidget {
  const _YearReviewBanner({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.tertiaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => context.push(AppRoutes.yearReview(year)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.onTertiaryContainer),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.yearReviewTitle(year),
                      style: theme.textTheme.titleMedium?.copyWith(color: scheme.onTertiaryContainer),
                    ),
                    Text(
                      l10n.yearReviewBannerBody,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
        ?trailing,
      ],
    ),
  );
}

// --- Today ---------------------------------------------------------------------

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = stats.goal == Duration.zero ? 1.0 : stats.today.inSeconds / stats.goal.inSeconds;
    final left = stats.goal - stats.today;
    return Card.filled(
      color: scheme.primaryContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Row(
          children: [
            Semantics(
              label: l10n.statsGoalPercent((fraction.clamp(0, 1) * 100).round()),
              child: SizedBox.square(
                dimension: 96,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.slow * 2,
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    painter: _RingPainter(
                      value: t,
                      track: scheme.onPrimaryContainer.withValues(alpha: 0.14),
                      color: scheme.primary,
                    ),
                    child: Center(
                      child: Icon(
                        fraction >= 1 ? Icons.check_rounded : Icons.headphones_rounded,
                        color: scheme.onPrimaryContainer,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.statsToday(formatDurationShort(l10n, stats.today)),
                    style: theme.textTheme.headlineSmall?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    fraction >= 1 ? l10n.statsGoalReached : l10n.statsGoalLeft(formatDurationShort(l10n, left)),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(Icons.local_fire_department_rounded, color: scheme.primary),
                        label: Text(l10n.statsStreak(stats.streak)),
                      ),
                      TextButton(
                        onPressed: () => showStatsGoalSheet(context),
                        style: TextButton.styleFrom(foregroundColor: scheme.onPrimaryContainer),
                        child: Text(l10n.statsGoalEdit),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daily goal and streak threshold. Also opened from Settings.
Future<void> showStatsGoalSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => const _GoalSheet(),
);

class _GoalSheet extends ConsumerWidget {
  const _GoalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goals = ref.watch(statsGoalsProvider).value ?? (goal: 30, streak: 5);
    final db = ref.read(globalDbProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.statsGoalTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in const [10, 15, 20, 30, 45, 60, 90, 120])
                ChoiceChip(
                  label: Text(l10n.statsGoalMinutes(m)),
                  selected: goals.goal == m,
                  onSelected: (_) => db.writeSetting(StatsSettings.goalMinutes, m.toString()),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(l10n.statsStreakRule(goals.streak), style: theme.textTheme.bodyLarge),
          Slider(
            value: goals.streak.toDouble().clamp(1, 30),
            min: 1,
            max: 30,
            divisions: 29,
            label: l10n.statsGoalMinutes(goals.streak),
            onChanged: (v) async {
              await db.writeSetting(StatsSettings.streakMinutes, v.round().toString());
              ref.invalidate(statsGoalsProvider);
            },
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.color});
  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

// --- Bars ------------------------------------------------------------------------

/// Bars with labels under them and a text alternative for screen readers.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, this.height = 120, this.highlight});
  final List<Duration> values;
  final List<String> labels;
  final double height;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = values.fold(Duration.zero, (a, b) => b > a ? b : a);
    final description = [
      for (var i = 0; i < values.length; i++) l10n.statsChartEntry(labels[i], formatDurationShort(l10n, values[i])),
    ].join(', ');
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: values.length > 12 ? 1 : Space.xs),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: peak == Duration.zero ? 0 : values[i].inSeconds / peak.inSeconds,
                        ),
                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.slow,
                        curve: Curves.easeOutCubic,
                        builder: (context, t, _) => Container(
                          height: math.max(3, height * t),
                          decoration: BoxDecoration(
                            color: i == highlight ? scheme.primary : scheme.primary.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(values.length > 12 ? 2 : 6),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    // Sparse labels on narrow bars (hours) may run wider
                    // than their bar.
                    overflow: TextOverflow.visible,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final change = stats.vsLastWeek;
    final changeText = change == null
        ? null
        : (change.abs() < 0.05
              ? l10n.statsVsLastWeekSame
              : (change > 0
                    ? l10n.statsVsLastWeekUp((change * 100).round())
                    : l10n.statsVsLastWeekDown((-change * 100).round())));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.statsThisWeek),
        _Bars(
          values: [for (final d in stats.week) d.time],
          labels: [for (final d in stats.week) DateFormat.E(locale).format(d.day)],
          highlight: 6,
        ),
        const SizedBox(height: Space.md),
        Text(l10n.statsAvgPerDay(formatDurationShort(l10n, stats.weekAverage)), style: theme.textTheme.bodyLarge),
        if (changeText != null)
          Text(changeText, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// --- Calendar -----------------------------------------------------------------------

class _CalendarSection extends StatefulWidget {
  const _CalendarSection({required this.stats});
  final StatsSnapshot stats;

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final days = widget.stats.days;
    final first = DateTime(_month.year, _month.month);
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final peak = days.values.fold(Duration.zero, (a, b) => b > a ? b : a);
    final now = DateTime.now();
    final canGoForward = DateTime(_month.year, _month.month + 1).isBefore(DateTime(now.year, now.month + 1));
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          l10n.statsCalendar,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.statsPreviousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Text(DateFormat.yMMM(locale).format(_month), style: theme.textTheme.labelLarge),
              IconButton(
                tooltip: l10n.statsNextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: canGoForward ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: Space.xs,
            crossAxisSpacing: Space.xs,
          ),
          itemCount: lead + count,
          itemBuilder: (context, i) {
            if (i < lead) return const SizedBox.shrink();
            final day = DateTime(_month.year, _month.month, i - lead + 1);
            final time = days[day] ?? Duration.zero;
            final level = peak == Duration.zero ? 0.0 : time.inSeconds / peak.inSeconds;
            final isSelected = selected == day;
            final filled = level > 0.5;
            return Semantics(
              button: true,
              selected: isSelected,
              label: l10n.statsDayTotal(DateFormat.MMMEd(locale).format(day), formatDurationShort(l10n, time)),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selected = day),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: time == Duration.zero
                        ? scheme.surfaceContainerHighest
                        : Color.lerp(scheme.primaryContainer, scheme.primary, level.clamp(0.0, 1.0)),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected ? Border.all(color: scheme.onSurface, width: 2) : null,
                  ),
                  child: Center(
                    child: Text(
                      day.day.toString(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: filled ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (selected != null) ...[
          const SizedBox(height: Space.md),
          Text(
            (days[selected] ?? Duration.zero) == Duration.zero
                ? l10n.statsDayNothing(DateFormat.MMMEd(locale).format(selected))
                : l10n.statsDayTotal(
                    DateFormat.MMMEd(locale).format(selected),
                    formatDurationShort(l10n, days[selected]!),
                  ),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}

// --- Totals ---------------------------------------------------------------------------

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tiles = [
      (Icons.schedule_rounded, l10n.statsTotalTime, formatDurationShort(l10n, stats.total)),
      (Icons.check_circle_outline_rounded, l10n.statsBooksFinished, stats.booksFinished.toString()),
      (Icons.timer_outlined, l10n.statsLongestSession, formatDurationShort(l10n, stats.longestSession)),
      (Icons.local_fire_department_outlined, l10n.statsLongestStreak, l10n.statsDays(stats.longestStreak)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.statsTotals),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 560 ? 4 : 2;
            final width = (box.maxWidth - Space.md * (columns - 1)) / columns;
            return Wrap(
              spacing: Space.md,
              runSpacing: Space.md,
              children: [
                for (final (icon, label, value) in tiles)
                  SizedBox(
                    width: width,
                    child: Card.outlined(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: theme.colorScheme.primary),
                            const SizedBox(height: Space.md),
                            Text(value, style: theme.textTheme.titleLarge),
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (stats.bookTime > stats.total + const Duration(minutes: 1)) ...[
          const SizedBox(height: Space.lg),
          Text(
            l10n.statsSpeedDividend(formatDurationShort(l10n, stats.bookTime), formatDurationShort(l10n, stats.total)),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}

// --- Rankings ---------------------------------------------------------------------------

class _TopBooks extends StatelessWidget {
  const _TopBooks({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.statsTopBooks),
        for (final e in stats.topBooks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CoverImage(source: e.book.cover, title: e.book.title, size: 48, radius: 8),
            title: Text(e.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: e.book.author == null ? null : Text(e.book.author!, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(formatDurationShort(l10n, e.time), style: theme.textTheme.labelLarge),
          ),
      ],
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.title, required this.entries});
  final String title;
  final List<Ranked> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = entries.first.time.inSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Text(formatDurationShort(l10n, e.time), style: theme.textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: Space.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: peak == 0 ? 0 : e.time.inSeconds / peak,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WhenSection extends StatelessWidget {
  const _WhenSection({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final monday = DateTime(2024, 1, 1);
    final caption = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.statsWhenYouListen),
        Text(l10n.statsByHour, style: caption),
        const SizedBox(height: Space.sm),
        _Bars(
          values: stats.hours,
          height: 80,
          labels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? l10n.statsHour(h) : ''],
        ),
        const SizedBox(height: Space.lg),
        Text(l10n.statsByWeekday, style: caption),
        const SizedBox(height: Space.sm),
        _Bars(
          values: stats.weekdays,
          height: 80,
          labels: [for (var i = 0; i < 7; i++) DateFormat.E(locale).format(monday.add(Duration(days: i)))],
        ),
      ],
    );
  }
}

class _FinishedSection extends StatelessWidget {
  const _FinishedSection({required this.stats});
  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.statsFinishedIn(stats.year)),
        LayoutBuilder(
          builder: (context, box) {
            final columns = (box.maxWidth / 110).floor().clamp(3, 8);
            final size = (box.maxWidth - Space.sm * (columns - 1)) / columns;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final b in stats.finishedThisYear)
                  CoverImage(source: b.cover, title: b.title, size: size, radius: Radii.cover / 1.5),
              ],
            );
          },
        ),
      ],
    );
  }
}
