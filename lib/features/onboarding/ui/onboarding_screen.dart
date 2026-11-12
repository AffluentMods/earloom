// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// First-run flow. Phase 1 adds "add server and sign in", Phase 8 the
/// welcome screens.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Text(AppLocalizations.of(context).appName, style: theme.textTheme.displaySmall),
      ),
    );
  }
}
