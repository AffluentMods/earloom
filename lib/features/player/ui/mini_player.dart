// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

/// The mini player that sits above the navigation bar on every tab.
///
/// Phase 0 reserves the slot. Nothing can be loaded yet, so it takes no
/// space. Phase 3 fills it in and shows it whenever an item is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
