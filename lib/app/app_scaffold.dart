// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/downloads/ui/offline_banner.dart';
import '../features/player/ui/mini_player.dart';
import '../l10n/gen/app_localizations.dart';

/// The shell around the four tabs: the current tab's own navigation stack,
/// the mini player slot above the navigation bar, then the bar itself.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: OfflineBanner(child: shell),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            // Tapping the current tab again pops it back to its first screen.
            onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: l10n.tabHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_books_outlined),
                selectedIcon: const Icon(Icons.library_books),
                label: l10n.tabLibrary,
              ),
              NavigationDestination(icon: const Icon(Icons.search), label: l10n.tabSearch),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: l10n.tabYou,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
