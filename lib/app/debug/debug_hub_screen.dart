// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'debug_routes.dart';
import 'demo_books.dart';

/// Entry point for the developer screens, plus the runtime theme switch.
class DebugHubScreen extends ConsumerWidget {
  const DebugHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(debugMenuLabel)),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Text('Theme', style: text.titleMedium),
          const SizedBox(height: Space.sm),
          SegmentedButton<AppThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('System')),
              ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: AppThemeMode.amoled, label: Text('AMOLED')),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => ref.read(themeModeProvider.notifier).set(selection.single),
          ),
          const SizedBox(height: Space.xl),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Cover colors'),
            subtitle: const Text('Sample covers next to the schemes derived from them'),
            onTap: () => context.push(DebugRoutes.colors),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Text('Design previews (fake data)', style: text.titleMedium),
          ),
          for (final (index, book) in demoBooks.indexed)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(Space.xs),
                child: Image(image: book.cover, width: 40, height: 40, fit: BoxFit.cover),
              ),
              title: Text(book.title),
              subtitle: Text(book.author),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_book_outlined),
                    tooltip: 'Item detail preview',
                    onPressed: () => context.push(DebugRoutes.designItem(index)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Now Playing preview',
                    onPressed: () => context.push(DebugRoutes.designPlayer(index)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
