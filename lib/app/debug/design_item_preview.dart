// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../theme/cover_surfaces.dart';
import '../theme/tokens.dart';
import 'demo_books.dart';
import 'design_widgets.dart';

/// Design preview of Item Detail with fake data, for sign-off on the look
/// before Phase 2 builds the real screen. Colors come from the cover scheme
/// that the surrounding CoverTheme provides.
class DesignItemPreview extends StatelessWidget {
  const DesignItemPreview({super.key, required this.book});

  final DemoBook book;

  static const _chapters = [
    ('Chapter 5', 'The Harbor Bell', '24 min'),
    ('Chapter 6', 'Low Water', '31 min'),
    ('Chapter 7', 'What the Tide Keeps', '28 min'),
    ('Chapter 8', 'Brass and Salt', '26 min'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [IconButton(icon: const Icon(Icons.more_horiz), tooltip: 'More', onPressed: () {})],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.heroTint, scheme.surface],
            stops: const [0, 0.6],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xxl),
            children: [
              Center(child: PreviewCover(image: book.cover, size: 232)),
              const SizedBox(height: Space.xl),
              Text(
                book.title,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: Space.sm),
              Text(
                book.author,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Narrated by ${book.narrator}',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (book.series != null) ...[
                const SizedBox(height: Space.md),
                Center(
                  child: ActionChip(
                    label: Text(book.series!),
                    avatar: const Icon(Icons.auto_stories_outlined, size: 18),
                    onPressed: () {},
                  ),
                ),
              ],
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: const Text('Resume  ·  3 hr 12 min left'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: Space.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: 0.64,
                  minHeight: 6,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.14),
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5 hr 41 min listened', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  Text('64%', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: Space.lg),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Action(icon: Icons.download_outlined, label: 'Download'),
                  _Action(icon: Icons.check_circle_outline, label: 'Finished'),
                  _Action(icon: Icons.playlist_add, label: 'Playlist'),
                  _Action(icon: Icons.ios_share, label: 'Share'),
                ],
              ),
              const SizedBox(height: Space.xl),
              Text(
                'A harbor town where every clock runs a little differently, and the one person who can '
                'set them right has just stopped believing in time. When the tide brings in a clock that '
                'runs backwards, the whole town starts to remember things that have not happened yet.',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface, height: 1.5),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text('More'),
                ),
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(child: Text('Chapters', style: text.titleMedium)),
                  Text('32 chapters', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: Space.sm),
              for (final (index, chapter) in _chapters.indexed)
                _ChapterRow(number: chapter.$1, title: chapter.$2, length: chapter.$3, current: index == 2),
              const SizedBox(height: Space.xl),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final genre in const ['Fiction', 'Fantasy', 'Small town', 'Slow burn']) Chip(label: Text(genre)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(Space.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.number, required this.title, required this.length, required this.current});

  final String number;
  final String title;
  final String length;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = current ? scheme.onSecondaryContainer : scheme.onSurface;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      decoration: BoxDecoration(
        color: current ? scheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(Space.md),
      ),
      child: Row(
        children: [
          if (current) ...[
            Icon(Icons.graphic_eq_rounded, size: 20, color: foreground),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(color: foreground)),
                Text(
                  number,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: current ? foreground : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            length,
            style: theme.textTheme.bodySmall?.copyWith(color: current ? foreground : scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
