// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/debug/debug_routes.dart';
import '../../../l10n/gen/app_localizations.dart';

/// The You tab: stats, downloads, settings and accounts will live here.
class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).tabYou),
        actions: [
          // Developer screens: debug builds only, never in a release.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: debugMenuLabel,
              onPressed: () => context.push(DebugRoutes.hub),
            ),
        ],
      ),
    );
  }
}
