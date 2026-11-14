// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';

/// What went wrong in plain words, with a button that copies the technical
/// details for a bug report.
class ErrorDetailsCard extends StatelessWidget {
  const ErrorDetailsCard({super.key, required this.message, required this.details, this.title, this.titleStyle});

  /// Optional first line, such as the book the error belongs to.
  final String? title;
  final TextStyle? titleStyle;
  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.sm, Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: (titleStyle ?? theme.textTheme.titleMedium)?.copyWith(color: scheme.onErrorContainer),
              ),
              const SizedBox(height: Space.xs),
            ],
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer, minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(l10n.genericCopyDetails),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: details));
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(l10n.genericDetailsCopied)));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
