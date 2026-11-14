// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/cover_surfaces.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/library/models.dart';
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
                    child: Column(
                      children: [
                        RefreshNotice(
                          error: refreshError,
                          padding: const EdgeInsets.only(bottom: Space.lg),
                        ),
                        artwork,
                        const SizedBox(height: Space.lg),
                        if (kicker != null)
                          Text(kicker!, style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: Space.xs),
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (primaryAction != null) ...[const SizedBox(height: Space.lg), primaryAction!],
                        if (below != null) ...[const SizedBox(height: Space.lg), below!],
                      ],
                    ),
                  ),
                ),
              ),
              ...slivers,
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
}
