// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/net/abs_errors.dart';
import '../../../../core/ui/states.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// A section heading with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.padding});

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.sm, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: text.sectionTitle),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Height of a card under a cover [coverWidth] wide: the cover, two title
/// lines and one line under them, at the current text size. Shelves use it
/// so titles never clip, whatever the text size.
double cardTextBlock(BuildContext context) {
  final theme = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  double measure(TextStyle? style, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: direction,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  // The same styles the cards use (BookGridCard, EpisodeCard).
  final title = measure(theme.titleSmall?.copyWith(height: 1.25), 'Ag\nAg');
  final line = measure(theme.bodySmall, 'Ag');
  return Space.sm + title + 2 + line + Space.xs;
}

double cardShelfHeight(BuildContext context, double coverWidth) => coverWidth + cardTextBlock(context);

/// A titled horizontal row of cards.
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.action,
    this.spacing = Space.lg,
  });

  final String title;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double height;
  final Widget? action;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(title: title, action: action),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: itemCount,
            separatorBuilder: (_, _) => SizedBox(width: spacing),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

/// A gray block shaped like the content that is about to load. Pulses
/// gently for a few seconds, unless the user asked for less motion.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = Space.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating && !_pulse.isCompleted) {
      // A few slow breaths, then still: content that takes longer than
      // that is better served by a calm placeholder than endless motion.
      _pulse.repeat(reverse: true, count: 4);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(scheme.surfaceContainerHigh, scheme.surfaceContainerHighest, _pulse.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A loading shelf: a heading bar and a row of cover shapes.
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key, this.coverSize = 136});

  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.md),
            child: SkeletonBox(width: 160, height: 18),
          ),
          SizedBox(
            height: coverSize + 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: Space.lg),
              itemBuilder: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: coverSize, height: coverSize, radius: Radii.cover),
                  const SizedBox(height: Space.sm),
                  SkeletonBox(width: coverSize * 0.8, height: 12),
                  const SizedBox(height: Space.xs),
                  SkeletonBox(width: coverSize * 0.5, height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A loading grid of cover shapes, as a sliver.
class SliverGridSkeleton extends StatelessWidget {
  const SliverGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(Space.lg),
      sliver: SliverGrid(
        gridDelegate: bookGridDelegate(context),
        delegate: SliverChildBuilderDelegate(
          (_, _) => const ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: SkeletonBox(height: double.infinity, radius: Radii.cover),
                ),
                SizedBox(height: Space.sm),
                SkeletonBox(width: 100, height: 12),
                SizedBox(height: Space.xs),
                SkeletonBox(width: 64, height: 10),
              ],
            ),
          ),
          childCount: 9,
        ),
      ),
    );
  }
}

/// The book grid: as many columns as fit at about 150 points, at least two.
/// Each cell is the square cover plus room for two title lines and an
/// author line at the current text size, so rows sit close together and
/// large text never clips.
SliverGridDelegate bookGridDelegate(BuildContext context) => _BookGridDelegate(cardTextBlock(context));

class _BookGridDelegate extends SliverGridDelegate {
  const _BookGridDelegate(this.textBlock);
  final double textBlock;

  static const _maxExtent = 180.0;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns = ((width + Space.lg) / (_maxExtent + Space.lg)).ceil().clamp(2, 12);
    final tile = (width - Space.lg * (columns - 1)) / columns;
    final extent = tile + textBlock;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: extent + Space.xl,
      crossAxisStride: tile + Space.lg,
      childMainAxisExtent: extent,
      childCrossAxisExtent: tile,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(_BookGridDelegate old) => old.textBlock != textBlock;
}

/// Shown above cached content when refreshing failed: offline, or another
/// error in plain words with a way to copy the details. Never replaces the
/// content itself.
class RefreshNotice extends StatelessWidget {
  const RefreshNotice({super.key, required this.error, this.padding});

  final Object? error;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e == null || e is AbsCancelled) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final offline = e is AbsUnreachable;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: InlineNotice(
        icon: offline ? Icons.cloud_off_rounded : Icons.sync_problem_rounded,
        message: offline ? l10n.offlineBanner : l10n.genericRefreshFailed,
        tone: offline ? NoticeTone.info : NoticeTone.warning,
        action: offline ? null : CopyDetailsButton(details: failureDetails(e)),
      ),
    );
  }
}

/// Technical details of an error, for "Copy details". Never a token: the
/// failures carry status and body text only.
String failureDetails(Object error) => error is AbsFailure ? error.details : error.toString();

class CopyDetailsButton extends StatelessWidget {
  const CopyDetailsButton({super.key, required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: details));
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.genericDetailsCopied)));
        }
      },
      child: Text(l10n.genericCopyDetails),
    );
  }
}

/// Shows an action error as a snack bar in plain words, with Copy details.
void showActionError(BuildContext context, Object error, {String? message}) {
  if (error is AbsCancelled) return;
  final l10n = AppLocalizations.of(context);
  final details = failureDetails(error);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message ?? l10n.genericActionFailed),
      action: SnackBarAction(
        label: l10n.genericCopyDetails,
        onPressed: () => Clipboard.setData(ClipboardData(text: details)),
      ),
    ),
  );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs refreshes for a screen and remembers the last failure for a
/// [RefreshNotice].
mixin RefreshingState<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Object? refreshError;

  Future<void> runRefresh(Future<void> Function() task) async {
    try {
      await task();
      if (mounted && refreshError != null) setState(() => refreshError = null);
    } on AbsCancelled {
      // A newer refresh took over.
    } on Object catch (e) {
      if (mounted) setState(() => refreshError = e);
    }
  }
}
