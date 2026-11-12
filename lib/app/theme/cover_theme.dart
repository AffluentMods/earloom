// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import 'app_theme.dart';
import 'tokens.dart';

/// Themes its subtree with the color scheme of a book cover.
///
/// Until the scheme is known the subtree keeps the surrounding theme, then
/// it animates over ([Motion.normal]). When the item or its cover changes,
/// the theme animates to the new cover.
class CoverTheme extends ConsumerStatefulWidget {
  const CoverTheme({
    super.key,
    required this.itemId,
    required this.coverUpdatedAt,
    required this.cover,
    required this.child,
  });

  final String itemId;
  final int coverUpdatedAt;

  /// A small version of the cover. It is only sampled for color.
  final ImageProvider cover;
  final Widget child;

  @override
  ConsumerState<CoverTheme> createState() => _CoverThemeState();
}

class _CoverThemeState extends ConsumerState<CoverTheme> {
  ColorScheme? _scheme;
  Brightness? _brightness;
  bool _amoled = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.brightnessOf(context);
    final amoled = ref.read(themeModeProvider) == AppThemeMode.amoled;
    if (brightness != _brightness || amoled != _amoled) {
      _brightness = brightness;
      _amoled = amoled;
      _resolve();
    }
  }

  @override
  void didUpdateWidget(CoverTheme old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId || old.coverUpdatedAt != widget.coverUpdatedAt || old.cover != widget.cover) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final request = ++_request;
    try {
      final scheme = await ref
          .read(coverSchemeServiceProvider)
          .schemeFor(
            itemId: widget.itemId,
            coverUpdatedAt: widget.coverUpdatedAt,
            cover: widget.cover,
            brightness: _brightness!,
            amoled: _amoled,
          );
      // A newer request (another book, another theme mode) wins.
      if (mounted && request == _request) setState(() => _scheme = scheme);
    } on Object {
      // A cover that fails to load or decode keeps the surrounding theme.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(themeModeProvider, (_, mode) {
      _amoled = mode == AppThemeMode.amoled;
      _resolve();
    });
    final scheme = _scheme;
    return AnimatedTheme(
      duration: Motion.normal,
      data: scheme == null ? Theme.of(context) : AppTheme.fromScheme(scheme),
      child: widget.child,
    );
  }
}
