// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/ui/cover_image.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import 'now_playing_screen.dart';
import 'player_widgets.dart';

/// Sits above the navigation bar on every tab while a book is loaded:
/// cover, title, chapter, a thin progress line, skip back and play.
/// Tap opens Now Playing; swipe down stops and clears.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const height = 68.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBook = ref.watch(playerProvider.select((s) => s.hasBook));
    return AnimatedSize(
      duration: Motion.normal,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: hasBook ? const NowPlayingTheme(child: _Bar()) : const SizedBox(width: double.infinity),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (now, chapter) = ref.watch(playerProvider.select((s) => (s.now, s.chapter)));
    if (now == null) return const SizedBox.shrink();
    final engine = ref.read(playerEngineProvider);
    final skipBack = ref.watch(playerPrefsProvider.select((p) => p.skipBack.inSeconds));
    final subtitle = (chapter != null && now.chapters.length > 1) ? chapter.title : now.author;
    return Dismissible(
      key: const ValueKey('mini-player'),
      direction: DismissDirection.down,
      confirmDismiss: (_) async {
        await HapticFeedback.mediumImpact();
        await engine.stop();
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.sm),
        child: Material(
          color: scheme.secondaryContainer,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shadowColor: scheme.shadow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.card - 4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.player),
            child: SizedBox(
              height: MiniPlayer.height,
              child: Stack(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: Space.sm),
                      CoverImage(
                        source: now.cover,
                        title: now.title,
                        size: 52,
                        radius: 10,
                        heroTag: nowPlayingCoverTag,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: l10n.playerOpen,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                now.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      IconTheme(
                        data: IconThemeData(color: scheme.onSecondaryContainer),
                        child: SkipButton(seconds: skipBack, forward: false, size: 30, onPressed: engine.skipBack),
                      ),
                      const PlayPauseButton(size: 52, filled: false),
                      const SizedBox(width: Space.xs),
                    ],
                  ),
                  const Positioned(left: 0, right: 0, bottom: 0, child: _ProgressLine()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends ConsumerWidget {
  const _ProgressLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = ref.watch(
      playerProvider.select((s) {
        final d = s.duration.inMilliseconds;
        return d <= 0 ? 0.0 : (s.position.inMilliseconds / d).clamp(0.0, 1.0);
      }),
    );
    return ExcludeSemantics(
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 3,
        backgroundColor: scheme.onSecondaryContainer.withValues(alpha: 0.12),
        color: scheme.primary,
      ),
    );
  }
}
