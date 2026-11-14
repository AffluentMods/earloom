// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/ui/home_screen.dart';
import '../features/item_detail/ui/item_detail_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/local_library/ui/import_books_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/player/ui/now_playing_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/you/ui/you_screen.dart';
import 'app_scaffold.dart';
import 'debug/debug_routes.dart';
import 'deep_links.dart';

/// Route locations, so screens never spell paths by hand.
abstract final class AppRoutes {
  static const home = '/home';
  static const library = '/library';
  static const search = '/search';
  static const you = '/you';
  static const player = '/player';
  static const onboarding = '/onboarding';
  static const localImport = '/local/import';
  static String item(String id) => '/item/${Uri.encodeComponent(id)}';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});

@visibleForTesting
GoRouter buildRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      // Deep links arrive as earloom://item/<id>. Rewrite them before any
      // route matching is trusted.
      final rewritten = normalizeDeepLink(state.uri);
      if (rewritten != null) return rewritten;
      // Phase 1: send to /onboarding when there is no active account.
      return null;
    },
    // A location that matches nothing (a bad deep link, an old shortcut)
    // lands on Home instead of an error page.
    onException: (context, state, router) => router.go(normalizeDeepLink(state.uri) ?? AppRoutes.home),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.library, builder: (_, _) => const LibraryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.you, builder: (_, _) => const YouScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/item/:id',
        builder: (_, state) => ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.player,
        pageBuilder: (_, state) => NowPlayingPage(key: state.pageKey),
      ),
      GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.localImport, builder: (_, _) => const ImportBooksScreen()),
      // Developer screens exist in debug builds only.
      if (kDebugMode) ...debugRoutes,
    ],
  );
}
