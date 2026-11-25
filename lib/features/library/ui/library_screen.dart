// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../../item_detail/ui/item_detail_screen.dart';
import '../../podcasts/ui/podcast_library_screen.dart';
import '../data/book_groups.dart';
import '../data/library_providers.dart';
import 'audiobooks_view.dart';
import 'listen_view.dart';
import 'lists_view.dart';
import 'widgets/browse_layout.dart';

/// The tabs of the Library tab, left to right.
enum LibraryTab { listen, audiobooks, podcasts, lists }

/// The Library tab: Listen (in progress, downloading, downloaded),
/// Audiobooks (the server's books and the books on this phone in one list),
/// Podcasts (when the server has a podcast library, or the user moved an
/// author's or a series' books there) and Lists (favorites, series,
/// authors, collections, playlists).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccount = ref.watch(accountSessionProvider) != null;
    final libraries = ref.watch(absLibrariesProvider);
    // The saved groups decide the Podcasts tab too: wait for them as well,
    // so the tabs do not change a moment after showing.
    final groups = ref.watch(bookGroupsProvider);
    if (hasAccount && (!libraries.hasValue || !groups.hasValue)) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).tabLibrary)),
        body: const CustomScrollView(slivers: [SliverGridSkeleton()]),
      );
    }
    final tabs = [
      LibraryTab.listen,
      LibraryTab.audiobooks,
      if (ref.watch(hasPodcastsTabProvider)) LibraryTab.podcasts,
      LibraryTab.lists,
    ];
    // A podcast library (or books moved to Podcasts) that appears or goes
    // away changes the tabs: start over with the new set.
    final view = _LibraryTabs(key: ValueKey(tabs.join(',')), tabs: tabs);
    if (MediaQuery.sizeOf(context).width < Breakpoints.expanded) return view;
    // Wide screens: the books on the left, the chosen book on the right.
    // Podcasts and Lists open their screens full width. The list stays the
    // first child either way, so switching tabs keeps its state.
    final tab = ref.watch(libraryTabProvider);
    final showPane = tab == LibraryTab.listen || tab == LibraryTab.audiobooks;
    final selected = ref.watch(libraryPaneProvider);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(flex: showPane ? 5 : 11, child: view),
        if (showPane) ...[
          const VerticalDivider(width: 1),
          Expanded(
            flex: 6,
            child: selected == null
                ? Scaffold(
                    body: EmptyState(icon: Icons.menu_book_outlined, title: l10n.libraryPickBook),
                  )
                : ItemDetailScreen(key: ValueKey(selected.key), itemId: selected.itemId, source: selected.source),
          ),
        ],
      ],
    );
  }
}

/// The book open in the Library tab's side pane on wide screens.
final libraryPaneProvider = NotifierProvider<LibraryPane, ItemRef?>(LibraryPane.new);

class LibraryPane extends Notifier<ItemRef?> {
  @override
  ItemRef? build() => null;

  void show(ItemRef? ref) => state = ref;
}

/// The Library tab on screen. Starts on Listen and stays where the user
/// left it while the app runs.
final libraryTabProvider = NotifierProvider<LibraryTabNotifier, LibraryTab>(LibraryTabNotifier.new);

class LibraryTabNotifier extends Notifier<LibraryTab> {
  @override
  LibraryTab build() => LibraryTab.listen;

  void set(LibraryTab tab) => state = tab;
}

class _LibraryTabs extends ConsumerStatefulWidget {
  const _LibraryTabs({super.key, required this.tabs});

  final List<LibraryTab> tabs;

  @override
  ConsumerState<_LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends ConsumerState<_LibraryTabs> with TickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: widget.tabs.length,
    vsync: this,
    initialIndex: widget.tabs.indexOf(ref.read(libraryTabProvider)).clamp(0, widget.tabs.length - 1),
  )..addListener(_onTab);

  void _onTab() {
    setState(() {});
    final tab = widget.tabs[_controller.index];
    if (ref.read(libraryTabProvider) != tab) ref.read(libraryTabProvider.notifier).set(tab);
  }

  @override
  void initState() {
    super.initState();
    // The tab on screen when the remembered one is gone (no podcasts).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(libraryTabProvider.notifier).set(widget.tabs[_controller.index]);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l10n, LibraryTab tab) => switch (tab) {
    LibraryTab.listen => l10n.libraryTabListen,
    LibraryTab.audiobooks => l10n.libraryTabAudiobooks,
    LibraryTab.podcasts => l10n.libraryTabPodcasts,
    LibraryTab.lists => l10n.libraryTabLists,
  };

  void _show(LibraryTab tab) {
    final index = widget.tabs.indexOf(tab);
    if (index >= 0) _controller.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Other screens (Home's See all) can ask for a tab.
    ref.listen(libraryTabProvider, (_, tab) {
      final index = widget.tabs.indexOf(tab);
      if (index >= 0 && index != _controller.index) _controller.animateTo(index);
    });
    final tab = widget.tabs[_controller.index];
    final grid = ref.watch(gridLayoutProvider(audiobooksLayoutKey)).value ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabLibrary),
        actions: [
          if (tab == LibraryTab.audiobooks)
            IconButton(
              icon: const Icon(Icons.library_add_outlined),
              tooltip: l10n.homeAddFiles,
              onPressed: () => context.push(AppRoutes.importFiles),
            ),
          const SizedBox(width: Space.xs),
        ],
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in widget.tabs) Tab(text: _label(l10n, t))],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          for (final t in widget.tabs)
            switch (t) {
              LibraryTab.listen => ListenView(onBrowse: () => _show(LibraryTab.audiobooks)),
              LibraryTab.audiobooks => AudiobooksView(grid: grid),
              LibraryTab.podcasts => const PodcastsTab(),
              LibraryTab.lists => const ListsView(),
            },
        ],
      ),
    );
  }
}

/// The grid or list choice of the Audiobooks tab.
const audiobooksLayoutKey = 'audiobooks';
