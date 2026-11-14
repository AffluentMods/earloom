// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/downloads/ui/offline_banner.dart';
import '../features/player/ui/mini_player.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme/tokens.dart';

/// The shell around the four tabs: the current tab's own navigation stack,
/// the mini player, and the navigation. Phones get a bottom bar under the
/// mini player; tablets and wide windows get a side rail, with the mini
/// player along the bottom of the content.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Tapping the current tab again pops it back to its first screen.
  void _select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final tabs = [
      (Icons.home_outlined, Icons.home, l10n.tabHome),
      (Icons.library_books_outlined, Icons.library_books, l10n.tabLibrary),
      (Icons.search, Icons.search, l10n.tabSearch),
      (Icons.person_outline, Icons.person, l10n.tabYou),
    ];
    if (width >= Breakpoints.medium) {
      return Scaffold(
        body: SafeArea(
          right: false,
          bottom: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                extended: false,
                groupAlignment: -0.85,
                destinations: [
                  for (final (icon, selected, label) in tabs)
                    NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: OfflineBanner(child: shell)),
                    // Not full width on big screens: a player bar the width
                    // of a TV is hard to read.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: const SafeArea(top: false, child: MiniPlayer()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: OfflineBanner(child: shell),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final (icon, selected, label) in tabs)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ],
      ),
    );
  }
}
