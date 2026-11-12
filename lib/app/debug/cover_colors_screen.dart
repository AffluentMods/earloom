// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import '../theme/tokens.dart';
import 'demo_books.dart';

/// Shows sample covers side by side with the color schemes derived from
/// them, in light and dark, to judge the extraction by eye.
class CoverColorsScreen extends ConsumerWidget {
  const CoverColorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cover colors')),
      body: ListView.separated(
        padding: const EdgeInsets.all(Space.lg),
        itemCount: demoBooks.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
        itemBuilder: (context, index) => _CoverRow(book: demoBooks[index]),
      ),
    );
  }
}

class _CoverRow extends ConsumerWidget {
  const _CoverRow({required this.book});

  final DemoBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(coverSchemeServiceProvider);
    Future<ColorScheme> scheme(Brightness brightness) =>
        service.schemeFor(itemId: book.id, coverUpdatedAt: 1, cover: book.cover, brightness: brightness);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.cover),
          child: Image(image: book.cover, width: 96, height: 96, fit: BoxFit.cover),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            spacing: Space.sm,
            children: [
              SchemeSwatch(scheme: scheme(Brightness.light), title: book.title),
              SchemeSwatch(scheme: scheme(Brightness.dark), title: book.title),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small card painted with a scheme: surface, the title in the on-surface
/// color, and the main role pairs as chips.
class SchemeSwatch extends StatelessWidget {
  const SchemeSwatch({super.key, required this.scheme, required this.title});

  final Future<ColorScheme> scheme;
  final String title;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ColorScheme>(
      future: scheme,
      builder: (context, snapshot) {
        final s = snapshot.data;
        if (s == null) return const SizedBox(height: 44);
        final text = Theme.of(context).textTheme;
        Widget chip(String label, Color background, Color foreground) => Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.pill)),
          child: Text(label, style: text.labelSmall?.copyWith(color: foreground)),
        );
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(Space.md),
            border: Border.all(color: s.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(color: s.onSurface),
              ),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  chip('primary', s.primary, s.onPrimary),
                  chip('container', s.primaryContainer, s.onPrimaryContainer),
                  chip('secondary', s.secondaryContainer, s.onSecondaryContainer),
                  chip('tertiary', s.tertiaryContainer, s.onTertiaryContainer),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
