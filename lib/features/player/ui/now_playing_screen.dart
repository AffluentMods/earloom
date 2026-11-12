// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';

/// The full-screen player, shown as a modal that slides up over the tabs.
/// Phase 0 only proves the route: the real screen arrives in Phase 3.
class NowPlayingPage extends CustomTransitionPage<void> {
  const NowPlayingPage({super.key})
    : super(
        fullscreenDialog: true,
        transitionDuration: Motion.normal,
        reverseTransitionDuration: Motion.normal,
        child: const NowPlayingScreen(),
        transitionsBuilder: _slideUp,
      );

  static Widget _slideUp(BuildContext context, Animation<double> animation, Animation<double> _, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
