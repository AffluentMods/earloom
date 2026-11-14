// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../util/html_sanitize.dart';

/// Server or tag HTML drawn as text through the sanitizer: paragraphs,
/// line breaks, bold, italic and safe links only. Collapsed to [maxLines]
/// with More and Less when it is longer.
class DescriptionText extends StatefulWidget {
  const DescriptionText({super.key, required this.html, this.maxLines = 6, this.style});

  final String html;
  final int maxLines;
  final TextStyle? style;

  @override
  State<DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<DescriptionText> {
  late SafeHtml _safe = sanitizeHtml(widget.html);
  final _recognizers = <TapGestureRecognizer>[];
  bool _expanded = false;

  @override
  void didUpdateWidget(DescriptionText old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _safe = sanitizeHtml(widget.html);
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _span(TextStyle base, Color linkColor) {
    _clearRecognizers();
    final children = <InlineSpan>[];
    for (final (i, paragraph) in _safe.paragraphs.indexed) {
      if (i > 0) children.add(const TextSpan(text: '\n\n'));
      for (final run in paragraph.runs) {
        final link = run.link;
        TapGestureRecognizer? recognizer;
        if (link != null) {
          recognizer = TapGestureRecognizer()..onTap = () => launchUrl(link, mode: LaunchMode.externalApplication);
          _recognizers.add(recognizer);
        }
        children.add(
          TextSpan(
            text: run.text,
            recognizer: recognizer,
            style: TextStyle(
              fontWeight: run.bold ? FontWeight.w600 : null,
              fontVariations: run.bold ? const [FontVariation.weight(600)] : null,
              fontStyle: run.italic ? FontStyle.italic : null,
              color: link != null ? linkColor : null,
              decoration: link != null ? TextDecoration.underline : null,
              decorationColor: link != null ? linkColor : null,
            ),
          ),
        );
      }
    }
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    if (_safe.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final base = widget.style ?? theme.textTheme.bodyLarge!.copyWith(color: theme.colorScheme.onSurface, height: 1.5);
    final span = _span(base, theme.colorScheme.primary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text.rich(
                span,
                maxLines: _expanded ? null : widget.maxLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            if (overflows || _expanded)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 44),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(_expanded ? l10n.itemDescriptionLess : l10n.itemDescriptionMore),
              ),
          ],
        );
      },
    );
  }
}
