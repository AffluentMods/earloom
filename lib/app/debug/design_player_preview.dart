// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../theme/cover_surfaces.dart';
import '../theme/tokens.dart';
import 'demo_books.dart';
import 'design_widgets.dart';

/// Design preview of Now Playing with fake data, for sign-off on the look
/// before Phase 3 builds the real player. The gradient is static here: the
/// real screen moves it slowly and holds it still under "reduce motion".
class DesignPlayerPreview extends StatelessWidget {
  const DesignPlayerPreview({super.key, required this.book});

  /// Natural width of the transport controls row: three 48 point buttons
  /// with their padding, two skip buttons and the 84 point play button come
  /// to 308 (measured on a 320 point wide emulator), plus a little room.
  static const _controlsWidth = 312.0;

  final DemoBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final muted = scheme.onSurfaceVariant;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: scheme.ambientGradient,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        book.series ?? 'Audiobooks',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(color: muted),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.more_horiz), tooltip: 'More', onPressed: () {}),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, box) => PreviewCover(
                        image: book.cover,
                        size: box.biggest.shortestSide.clamp(120.0, 340.0),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headlineMedium),
                ),
                const SizedBox(height: Space.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(book.author, style: text.bodyLarge?.copyWith(color: muted)),
                ),
                const SizedBox(height: Space.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'What the Tide Keeps',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text('Chapter 7 of 32', style: text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    overlayShape: SliderComponentShape.noOverlay,
                    trackHeight: 5,
                    padding: const EdgeInsets.symmetric(vertical: Space.md),
                  ),
                  child: Slider(value: 0.42, onChanged: (_) {}),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('11:46', style: text.bodySmall?.copyWith(color: muted)),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        '16 min left',
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // On phones narrower than the controls need, the whole row
                // scales down instead of overflowing.
                LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: box.maxWidth < _controlsWidth ? _controlsWidth : box.maxWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            iconSize: 36,
                            tooltip: 'Previous chapter',
                            onPressed: () {},
                          ),
                          const SkipButton(seconds: 15, forward: false),
                          IconButton.filled(
                            icon: const Icon(Icons.pause_rounded),
                            iconSize: 44,
                            tooltip: 'Pause',
                            style: IconButton.styleFrom(minimumSize: const Size(84, 84)),
                            onPressed: () {},
                          ),
                          const SkipButton(seconds: 30, forward: true),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            iconSize: 36,
                            tooltip: 'Next chapter',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(foregroundColor: scheme.onSurface, minimumSize: const Size(48, 48)),
                      child: Text('1.2x', style: text.labelLarge),
                    ),
                    IconButton(icon: const Icon(Icons.bedtime_outlined), tooltip: 'Sleep timer', onPressed: () {}),
                    IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Bookmark', onPressed: () {}),
                    IconButton(
                      icon: const Icon(Icons.format_list_bulleted_rounded),
                      tooltip: 'Chapters',
                      onPressed: () {},
                    ),
                    IconButton(icon: const Icon(Icons.speaker_group_outlined), tooltip: 'Output', onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
