// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// Material window size classes, from a width in logical pixels.
enum WindowSize {
  compact,
  medium,
  expanded,
  large;

  static WindowSize of(double width) {
    if (width >= Breakpoints.large) return large;
    if (width >= Breakpoints.expanded) return expanded;
    if (width >= Breakpoints.medium) return medium;
    return compact;
  }

  bool atLeast(WindowSize other) => index >= other.index;
}

/// Widths that keep content comfortable on big screens.
abstract final class ContentWidth {
  /// Text, settings and other lists of rows.
  static const reading = 720.0;

  /// Forms and short centered content (empty states, welcome).
  static const form = 560.0;
}

/// Space between the content and the sides of its area: a phone's 16, more
/// on tablets, so shelves and grids never run into the edge or the rail.
double pageGutter(double width) => switch (WindowSize.of(width)) {
  WindowSize.compact => Space.lg,
  WindowSize.medium => Space.xl,
  _ => Space.xxl,
};

extension PageLayout on BuildContext {
  /// The page gutter for the current window.
  double get gutter => pageGutter(MediaQuery.sizeOf(this).width);

  /// The size class of the current window.
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);
}

/// Cover width of the cards on a shelf: bigger on tablets, where 136 points
/// leaves rows of postage stamps.
double shelfCoverWidth(BuildContext context) => switch (context.windowSize) {
  WindowSize.compact => 136,
  WindowSize.medium => 152,
  _ => 168,
};

/// Side padding that centers a column at most [maxWidth] wide in [width].
EdgeInsets centeredInsets(double width, {double maxWidth = ContentWidth.reading}) =>
    EdgeInsets.symmetric(horizontal: math.max(0, (width - maxWidth) / 2));

/// Builds a page with the side padding that keeps its content in a centered,
/// readable column on big screens. On phones the padding is zero, so the
/// page looks exactly as it would without this.
///
/// Wrap the whole Scaffold, so the app bar can line its title up with the
/// column through [alignedTitleSpacing].
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.builder, this.maxWidth = ContentWidth.reading});

  final double maxWidth;
  final Widget Function(BuildContext context, EdgeInsets sides) builder;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => builder(context, centeredInsets(box.maxWidth, maxWidth: maxWidth)));
}

/// A [ListView] that keeps its rows in a centered, readable column on big
/// screens. The scroll view itself stays full width, so dragging anywhere
/// scrolls and the scroll bar sits at the edge of the screen.
class ReadableListView extends StatelessWidget {
  const ReadableListView({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior,
    this.maxWidth = ContentWidth.reading,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ListView(
      controller: controller,
      physics: physics,
      keyboardDismissBehavior: keyboardDismissBehavior,
      padding: padding.add(centeredInsets(box.maxWidth, maxWidth: maxWidth)),
      children: children,
    ),
  );
}

/// The sliver version of [ReadableListView]: centers [sliver] in a readable
/// column on big screens.
class SliverReadable extends StatelessWidget {
  const SliverReadable({super.key, required this.sliver, this.maxWidth = ContentWidth.reading});

  final Widget sliver;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverPadding(
      padding: centeredInsets(constraints.crossAxisExtent, maxWidth: maxWidth),
      sliver: sliver,
    ),
  );
}

/// App bar title spacing that puts the title over a readable column whose
/// rows start [sides.left] plus a list tile's 16 points in. With a back
/// button the title moves over by less, so it still lines up.
double alignedTitleSpacing(BuildContext context, EdgeInsets sides) {
  if (sides.left == 0) return NavigationToolbar.kMiddleSpacing;
  final hasLeading = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
  final target = sides.left + Space.lg;
  return math.max(NavigationToolbar.kMiddleSpacing, target - (hasLeading ? kToolbarHeight : 0));
}

/// Reports no intrinsic height, so a scrolling panel inside an
/// [IntrinsicHeight] row takes the height of its neighbours instead of
/// asking for its own.
class NoIntrinsicHeight extends SingleChildRenderObjectWidget {
  const NoIntrinsicHeight({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNoIntrinsicHeight();
}

class _RenderNoIntrinsicHeight extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
