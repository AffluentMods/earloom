// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/ui/states.dart';
import '../../../core/util/duration_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/stats_repository.dart';
import '../data/year_review.dart';

/// Swipeable story cards for one year. Each card can be shared as an image;
/// only that image leaves the phone, and only when the user shares it.
class YearReviewScreen extends ConsumerStatefulWidget {
  const YearReviewScreen({super.key, required this.year});
  final int year;

  @override
  ConsumerState<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends ConsumerState<YearReviewScreen> {
  final _page = PageController(viewportFraction: 0.86);
  final _keys = <GlobalKey>[];
  int _index = 0;
  bool _sharing = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_index >= _keys.length || _sharing) return;
    final boundary = _keys[_index].currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'earloom_${widget.year}_${_index + 1}.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final review = ref.watch(yearReviewProvider(widget.year));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.yearReviewTitle(widget.year))),
      body: switch (review) {
        AsyncData(:final value) when value.isEmpty => EmptyState(
          icon: Icons.auto_stories_outlined,
          title: l10n.yearReviewTitle(widget.year),
          body: l10n.yearReviewEmpty(widget.year),
        ),
        AsyncData(:final value) => _cards(context, value),
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: ErrorNotice(message: l10n.genericSomethingWentWrong, details: '$error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _cards(BuildContext context, YearReview r) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final cards = <Widget>[
      _Card(lead: l10n.yearReviewHoursLead, value: formatDurationShort(l10n, r.time), year: r.year),
      _Card(
        lead: l10n.yearReviewBooksLead,
        value: l10n.yearReviewBooks(r.finished.length),
        year: r.year,
        covers: r.finished,
      ),
      if (r.topAuthor != null)
        _Card(
          lead: l10n.yearReviewTopAuthorLead,
          value: r.topAuthor!.name,
          detail: formatDurationShort(l10n, r.topAuthor!.time),
          year: r.year,
        ),
      if (r.topNarrator != null)
        _Card(
          lead: l10n.yearReviewTopNarratorLead,
          value: r.topNarrator!.name,
          detail: formatDurationShort(l10n, r.topNarrator!.time),
          year: r.year,
        ),
      if (r.longestStreak > 1)
        _Card(lead: l10n.yearReviewStreakLead, value: l10n.statsDays(r.longestStreak), year: r.year),
      if (r.busiestMonth != null)
        _Card(
          lead: l10n.yearReviewBusiestMonthLead,
          value: DateFormat.MMMM(locale).format(DateTime(r.year, r.busiestMonth!)),
          year: r.year,
        ),
      if (r.favoriteHour != null)
        _Card(
          lead: l10n.yearReviewFavoriteHourLead,
          value: MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: r.favoriteHour!, minute: 0)),
          year: r.year,
        ),
      if (r.bookTime > r.time + const Duration(minutes: 30))
        _Card(
          lead: l10n.yearReviewSpeedLead,
          value: formatDurationShort(l10n, r.bookTime),
          detail: l10n.yearReviewSpeedTail(formatDurationShort(l10n, r.time)),
          year: r.year,
        ),
    ];
    while (_keys.length < cards.length) {
      _keys.add(GlobalKey());
    }
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _page,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Semantics(
              label: l10n.yearReviewCardOf(i + 1, cards.length),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.lg),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: RepaintBoundary(key: _keys[i], child: cards[i]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: FilledButton.icon(
            onPressed: _sharing ? null : _share,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(l10n.yearReviewShare),
          ),
        ),
      ],
    );
  }
}

/// One 9:16 story card in the theme's colors.
class _Card extends StatelessWidget {
  const _Card({required this.lead, required this.value, required this.year, this.detail, this.covers = const []});

  final String lead;
  final String value;
  final String? detail;
  final int year;
  final List<StatsBook> covers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = scheme.onPrimaryContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sheet),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, Color.lerp(scheme.primaryContainer, scheme.secondaryContainer, 0.6)!],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.yearReviewTitle(year), style: theme.textTheme.labelLarge?.copyWith(color: on)),
                const Spacer(),
                Text(lead, style: theme.textTheme.titleLarge?.copyWith(color: on)),
                const SizedBox(height: Space.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth),
                    child: Text(value, style: theme.textTheme.displayMedium?.copyWith(color: on, height: 1.1)),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(detail!, style: theme.textTheme.titleMedium?.copyWith(color: on)),
                ],
                if (covers.isNotEmpty) ...[
                  const SizedBox(height: Space.xl),
                  _Collage(books: covers, width: box.maxWidth),
                ],
                const Spacer(),
                Text(l10n.appName, style: theme.textTheme.titleSmall?.copyWith(color: on)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Collage extends StatelessWidget {
  const _Collage({required this.books, required this.width});
  final List<StatsBook> books;
  final double width;

  @override
  Widget build(BuildContext context) {
    const columns = 4;
    final size = (width - Space.xs * (columns - 1)) / columns;
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final b in books.take(12)) CoverImage(source: b.cover, title: b.title, size: size, radius: 8),
      ],
    );
  }
}
