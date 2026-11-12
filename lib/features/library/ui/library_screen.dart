// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// The Library tab. Phase 0 only reserves the screen: content arrives in Phase 2.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).tabLibrary)),
    );
  }
}
