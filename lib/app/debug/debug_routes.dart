// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/account_db.dart';
import '../providers.dart';
import '../theme/cover_theme.dart';
import 'cover_colors_screen.dart';
import 'debug_hub_screen.dart';
import 'demo_books.dart';
import 'design_item_preview.dart';
import 'design_player_preview.dart';

// Everything under lib/app/debug is for developers and design review. The
// routes are only registered in debug builds, so the plain English strings
// in this folder never reach a user and stay out of the translation files.

const debugMenuLabel = 'Developer screens';

abstract final class DebugRoutes {
  static const hub = '/debug';
  static const colors = '/debug/colors';
  static String designItem(int book) => '/debug/design/item/$book';
  static String designPlayer(int book) => '/debug/design/player/$book';
}

final debugRoutes = <RouteBase>[
  ShellRoute(
    // There is no account yet in Phase 0, so the developer screens get a
    // throwaway in-memory account database of their own.
    builder: (context, state, child) => ProviderScope(
      overrides: [
        accountDbProvider.overrideWith((ref) {
          final db = AccountDb(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
      child: child,
    ),
    routes: [
      GoRoute(path: DebugRoutes.hub, builder: (_, _) => const DebugHubScreen()),
      GoRoute(path: DebugRoutes.colors, builder: (_, _) => const CoverColorsScreen()),
      GoRoute(
        path: '/debug/design/item/:book',
        builder: (_, state) => _themed(state, (book) => DesignItemPreview(book: book)),
      ),
      GoRoute(
        path: '/debug/design/player/:book',
        builder: (_, state) => _themed(state, (book) => DesignPlayerPreview(book: book)),
      ),
    ],
  ),
];

Widget _themed(GoRouterState state, Widget Function(DemoBook book) build) {
  final index = (int.tryParse(state.pathParameters['book'] ?? '') ?? 0).clamp(0, demoBooks.length - 1);
  final book = demoBooks[index];
  return CoverTheme(itemId: book.id, coverUpdatedAt: 1, cover: book.cover, child: build(book));
}
