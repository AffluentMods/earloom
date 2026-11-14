// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show Widget;

import '../features/accounts/ui/accounts_screen.dart';
import '../features/accounts/ui/add_server_screen.dart';
import '../features/downloads/ui/download_settings_screen.dart';
import '../features/downloads/ui/downloads_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../core/library/browse_models.dart';
import '../core/library/source_id.dart';
import '../features/item_detail/ui/item_detail_screen.dart';
import '../features/library/ui/author_screen.dart';
import '../features/library/ui/book_list_screen.dart';
import '../features/library/ui/browse_not_found.dart';
import '../features/library/ui/library_screen.dart';
import '../features/library/ui/filtered_books_screen.dart';
import '../features/library/ui/series_screen.dart';
import '../features/local_library/ui/import_books_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/player/player_controller.dart';
import '../features/player/ui/now_playing_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/stats/ui/stats_screen.dart';
import '../features/stats/ui/year_review_screen.dart';
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
  static const stats = '/you/stats';
  static String yearReview(int year) => '/you/stats/year/$year';
  static const settings = '/you/settings';
  static const settingsPlayback = '/you/settings/playback';
  static const settingsAppearance = '/you/settings/appearance';
  static const settingsPrivacy = '/you/settings/privacy';
  static const settingsAbout = '/you/settings/about';
  static const downloads = '/you/downloads';
  static const downloadSettings = '/you/downloads/settings';
  static const importFiles = '/local/import';
  static String item(String id) => '/item/${Uri.encodeComponent(id)}';

  /// The browse routes below exist inside the Home, Library and Search tabs
  /// (so the tab bar and mini player stay) and at the top level. [base] is
  /// the tab root (`/home`) or empty for the top level.
  static String book(ItemRef ref, {String base = ''}) => _browse(base, 'book', ref.source, ref.itemId);
  static String series(SourceId source, String id, {String base = ''}) => _browse(base, 'series', source, id);
  static String author(SourceId source, String id, {String base = ''}) => _browse(base, 'author', source, id);

  /// Books of one library with one filter (a narrator, a genre, a tag).
  static String filtered(SourceId source, String libraryId, FilterKind kind, String value, {String base = ''}) =>
      '$base/filtered/${Uri.encodeComponent(source.key)}/${Uri.encodeComponent(libraryId)}/${kind.name}/'
      '${Uri.encodeComponent(value)}';
  static String collection(SourceId source, String id, {String base = ''}) => _browse(base, 'collection', source, id);
  static String playlist(SourceId source, String id, {String base = ''}) => _browse(base, 'playlist', source, id);

  static String _browse(String base, String kind, SourceId source, String id) =>
      '$base/$kind/${Uri.encodeComponent(source.key)}/${Uri.encodeComponent(id)}';

  /// Tab roots that host the browse routes.
  static const browseBases = [home, library, search];
}

/// What a browse route needs from its location: the source and the id.
(SourceId, String)? _browseArgs(GoRouterState state, String idParam) {
  final source = SourceId.tryParse(state.pathParameters['source'] ?? '');
  final id = state.pathParameters[idParam];
  if (source == null || id == null || id.isEmpty) return null;
  return (source, id);
}

/// Book, series, author, narrator, collection and playlist screens. [top]
/// makes absolute paths for the top level.
List<RouteBase> browseRoutes({bool top = false}) {
  final p = top ? '/' : '';
  Widget missing() => const BrowseNotFound();
  return [
    GoRoute(
      path: '${p}book/:source/:id',
      builder: (_, state) {
        final args = _browseArgs(state, 'id');
        if (args == null) return missing();
        return ItemDetailScreen(itemId: args.$2, source: args.$1, heroTag: state.extra);
      },
    ),
    GoRoute(
      path: '${p}series/:source/:id',
      builder: (_, state) {
        final args = _browseArgs(state, 'id');
        return args == null ? missing() : SeriesScreen(source: args.$1, seriesId: args.$2);
      },
    ),
    GoRoute(
      path: '${p}author/:source/:id',
      builder: (_, state) {
        final args = _browseArgs(state, 'id');
        return args == null ? missing() : AuthorScreen(source: args.$1, authorId: args.$2);
      },
    ),
    GoRoute(
      path: '${p}filtered/:source/:library/:kind/:value',
      builder: (_, state) {
        final args = _browseArgs(state, 'value');
        final kind = FilterKind.values.asNameMap()[state.pathParameters['kind']];
        final library = state.pathParameters['library'];
        if (args == null || kind == null || library == null) return missing();
        return FilteredBooksScreen(source: args.$1, libraryId: library, filter: LibraryFilter(kind, args.$2));
      },
    ),
    GoRoute(
      path: '${p}collection/:source/:id',
      builder: (_, state) {
        final args = _browseArgs(state, 'id');
        return args == null ? missing() : BookListScreen.collection(source: args.$1, id: args.$2);
      },
    ),
    GoRoute(
      path: '${p}playlist/:source/:id',
      builder: (_, state) {
        final args = _browseArgs(state, 'id');
        return args == null ? missing() : BookListScreen.playlist(source: args.$1, id: args.$2);
      },
    ),
  ];
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
            routes: [GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen(), routes: browseRoutes())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: AppRoutes.library, builder: (_, _) => const LibraryScreen(), routes: browseRoutes()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchScreen(), routes: browseRoutes()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.you,
                builder: (_, _) => const YouScreen(),
                routes: [
                  GoRoute(path: 'accounts', builder: (_, _) => const AccountsScreen()),
                  GoRoute(
                    path: 'stats',
                    builder: (_, _) => const StatsScreen(),
                    routes: [
                      GoRoute(
                        path: 'year/:year',
                        builder: (_, state) => YearReviewScreen(
                          year: int.tryParse(state.pathParameters['year'] ?? '') ?? DateTime.now().year,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const SettingsScreen(),
                    routes: [
                      GoRoute(path: 'playback', builder: (_, _) => const PlaybackSettingsScreen()),
                      GoRoute(path: 'appearance', builder: (_, _) => const AppearanceSettingsScreen()),
                      GoRoute(path: 'privacy', builder: (_, _) => const PrivacySettingsScreen()),
                      GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
                    ],
                  ),
                  GoRoute(
                    path: 'downloads',
                    builder: (_, _) => const DownloadsScreen(),
                    routes: [GoRoute(path: 'settings', builder: (_, _) => const DownloadSettingsScreen())],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // `earloom://item/<id>`: an item of the current account.
      GoRoute(
        path: '/item/:id',
        builder: (_, state) => ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      ...browseRoutes(top: true),
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
