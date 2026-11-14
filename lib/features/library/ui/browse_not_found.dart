// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../../core/ui/states.dart';
import '../../../l10n/gen/app_localizations.dart';

/// A browse link that cannot be read (a broken or hand-edited location).
class BrowseNotFound extends StatelessWidget {
  const BrowseNotFound({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(icon: Icons.link_off_rounded, title: AppLocalizations.of(context).browseNotFound),
    );
  }
}
