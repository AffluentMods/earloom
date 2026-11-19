// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/cover_surfaces.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/library/models.dart';
import '../../../../core/ui/adaptive.dart';
import 'book_cover.dart';
import 'browse_layout.dart';

/// The frame of a screen about a group of books (series, author, narrator,
/// collection, playlist): themed with the first cover, a tinted header with
/// artwork, name and actions, then the books.
class CollectionScaffold extends StatelessWidget {
  const CollectionScaffold({
    super.key,
    required this.title,
    required this.artwork,
    required this.slivers,
    this.themeBook,
    this.kicker,
    this.subtitle,
    this.primaryAction,
    this.actions = const [],
    this.refreshError,
    this.onRefresh,
    this.below,
  });

  final String title;

  /// Small text above the title ("Narrator").
  final String? kicker;
  final String? subtitle;
  final Widget artwork;
  final BookSummary? themeBook;
  final Widget? primaryAction;

  /// App bar actions.
  final List<Widget> actions;

  /// Under the primary action (a description).
  final Widget? below;
  final List<Widget> slivers;
  final Object? refreshError;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return BookCoverTheme(
      book: themeBook,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          final scroll = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: scheme.heroTint,
                surfaceTintColor: Colors.transparent,
                actions: actions,
              ),
              SliverToBoxAdapter(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [scheme.heroTint, scheme.surface],
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final sides = centeredInsets(box.maxWidth, maxWidth: _maxWidth);
                      final wide = box.maxWidth - sides.horizontal >= _sideBySideFrom;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          sides.left + Space.xl,
                          0,
                          sides.right + Space.xl,
                          wide ? Space.xl : Space.lg,
                        ),
                        child: Column(
                          children: [
                            RefreshNotice(
                              error: refreshError,
                              padding: const EdgeInsets.only(bottom: Space.lg),
                            ),
                            if (wide)
                              // Tablets: the artwork beside the name and
                              // actions, not a phone's stack in the middle.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  artwork,
                                  const SizedBox(width: Space.xxl),
                                  Expanded(child: _titleBlock(text, scheme, start: true)),
                                ],
                              )
                            else ...[
                              artwork,
                              const SizedBox(height: Space.lg),
                              _titleBlock(text, scheme, start: false),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Rows and grids keep a sensible width on big screens.
              for (final sliver in slivers) SliverReadable(maxWidth: _maxWidth, sliver: sliver),
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xxl)),
            ],
          );
          return Scaffold(
            backgroundColor: scheme.surface,
            body: onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
          );
        },
      ),
    );
  }

  static const _maxWidth = 960.0;

  /// Content width from which the artwork sits beside the title.
  static const _sideBySideFrom = 640.0;

  Widget _titleBlock(TextTheme text, ColorScheme scheme, {required bool start}) {
    final align = start ? TextAlign.start : TextAlign.center;
    return Column(
      crossAxisAlignment: start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (kicker != null) Text(kicker!, style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: align,
            style: (start ? text.displaySmall : text.headlineMedium)?.copyWith(color: scheme.onSurface),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            subtitle!,
            textAlign: align,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (primaryAction != null) ...[
          const SizedBox(height: Space.lg),
          if (start)
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: primaryAction)
          else
            primaryAction!,
        ],
        if (below != null) ...[const SizedBox(height: Space.lg), below!],
      ],
    );
  }
}
