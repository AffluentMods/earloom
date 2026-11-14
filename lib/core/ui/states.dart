// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';
import '../../l10n/gen/app_localizations.dart';

/// An error in plain words, with a way to copy the technical details.
/// Every error the user can see goes through this widget.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.details, this.action});

  final String message;

  /// Copied to the clipboard by "Copy details". Never contains a token.
  final String? details;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(Space.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(message, style: text.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
                ),
              ],
            ),
            if (details != null || action != null) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                alignment: WrapAlignment.end,
                children: [
                  ?action,
                  if (details != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: details!));
                        if (context.mounted) {
                          ScaffoldMessenger.maybeOf(
                            context,
                          )?.showSnackBar(SnackBar(content: Text(l10n.genericDetailsCopied)));
                        }
                      },
                      child: Text(l10n.genericCopyDetails),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A calm notice inside content (not an error): cleartext warnings,
/// "sign in again", security advisories.
class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.icon, required this.message, this.action, this.tone = NoticeTone.info});

  final IconData icon;
  final String message;
  final Widget? action;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      NoticeTone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      NoticeTone.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Space.lg)),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground)),
          ),
          if (action != null) ...[const SizedBox(width: Space.sm), action!],
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning }

/// One sentence and one action, for a screen or section with nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: Space.lg),
            Text(title, textAlign: TextAlign.center, style: text.titleMedium),
            if (body != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}
