// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/ui/accounts_screen.dart';
import '../features/accounts/ui/add_server_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/item_detail/ui/item_detail_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/local_library/ui/import_books_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/player/player_controller.dart';
import '../features/player/ui/now_playing_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/you/ui/you_screen.dart';
import 'app_scaffold.dart';
import 'debug/debug_routes.dart';
import 'providers.dart';
import 'deep_links.dart';

/// Route locations, so screens never spell paths by hand.
abstract final class AppRoutes {
  static const home = '/home';
  static const library = '/library';
  static const search = '/search';
  static const you = '/you';
  static const player = '/player';
  static const onboarding = '/onboarding';
  static const addServer = '/accounts/add';
  static const accounts = '/you/accounts';
  static const importFiles = '/local/import';
  static String item(String id) => '/item/${Uri.encodeComponent(id)}';
}

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(onboardingProvider));
  ref.listen(onboardingProvider, (_, value) => onboarded.value = value);
  final router = buildRouter(onboarded: onboarded, hasBook: () => ref.read(playerProvider).hasBook);
  ref.onDispose(router.dispose);
  ref.onDispose(onboarded.dispose);
  return router;
});

/// Locations reachable before onboarding is done.
const _onboardingRoutes = ['/onboarding', '/accounts/add', '/local/import'];

@visibleForTesting
GoRouter buildRouter({
  String initialLocation = AppRoutes.home,
  ValueListenable<bool>? onboarded,
  bool Function()? hasBook,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: onboarded,
    redirect: (context, state) {
      // Deep links arrive as earloom://item/<id>. Rewrite them before any
      // route matching is trusted.
      final rewritten = normalizeDeepLink(state.uri);
      if (rewritten != null) return rewritten;
      final location = state.uri.path;
      final isOnboardingRoute = _onboardingRoutes.any(location.startsWith);
      if (onboarded != null && !onboarded.value && !isOnboardingRoute && !location.startsWith('/debug')) {
        return AppRoutes.onboarding;
      }
      if (onboarded != null && onboarded.value && location == AppRoutes.onboarding) return AppRoutes.home;
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
            routes: [
              GoRoute(
                path: AppRoutes.you,
                builder: (_, _) => const YouScreen(),
                routes: [GoRoute(path: 'accounts', builder: (_, _) => const AccountsScreen())],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/item/:id',
        builder: (_, state) => ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.player,
        // A link to the player with nothing loaded has nothing to show.
        redirect: (_, _) => (hasBook?.call() ?? true) ? null : AppRoutes.home,
        pageBuilder: (_, state) => NowPlayingPage(key: state.pageKey),
      ),
      GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.addServer, builder: (_, _) => const AddServerScreen()),
      GoRoute(
        path: '/accounts/:id/signin',
        builder: (_, state) => AddServerScreen(reauthAccountId: state.pathParameters['id']),
      ),
      GoRoute(path: AppRoutes.importFiles, builder: (_, _) => const ImportBooksScreen()),
      // Developer screens exist in debug builds only.
      if (kDebugMode) ...debugRoutes,
    ],
  );
}
