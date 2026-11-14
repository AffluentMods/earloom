// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/cover_theme.dart';
import '../../../core/ui/cover_image.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../player_controller.dart';
import '../player_engine.dart';

/// "4:05", "1:02:03". Digits and colons only, the same in every language.
String formatClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "1x", "1.25x".
String formatSpeed(AppLocalizations l10n, double speed) {
  var text = speed.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return l10n.playerSpeedValue(text);
}

/// A number that changes when the cover changes, for the color cache.
int coverRevision(String? coverKey) {
  if (coverKey == null) return 0;
  final tail = int.tryParse(coverKey.split(RegExp(r'[-_.]')).where((p) => int.tryParse(p) != null).lastOrNull ?? '');
  if (tail != null) return tail;
  // FNV-1a: stable across runs, unlike String.hashCode guarantees.
  var hash = 0x811c9dc5;
  for (final unit in coverKey.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// A small version of a cover, only for picking colors.
ImageProvider? coverSample(CoverSource? source) => switch (source) {
  FileCover(:final path) => ResizeImage(FileImage(File(path)), width: 128),
  NetworkCover(:final itemCoverUrl, :final cacheKey, :final headers) => CachedNetworkImageProvider(
    itemCoverUrl.replace(queryParameters: {'width': '128', 'format': 'webp'}).toString(),
    cacheKey: '$cacheKey-128',
    headers: headers,
  ),
  null => null,
};

/// Themes [child] with the playing book's cover colors.
class NowPlayingTheme extends ConsumerWidget {
  const NowPlayingTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(playerProvider.select((s) => s.now));
    final sample = coverSample(now?.cover);
    if (now == null || sample == null) return child;
    return CoverTheme(itemId: now.ref.key, coverUpdatedAt: coverRevision(now.coverKey), cover: sample, child: child);
  }
}

/// The play/pause button. Shows a ring while audio loads.
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, this.size = 84, this.filled = true});
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (playing, buffering) = ref.watch(playerProvider.select((s) => (s.playing, s.buffering)));
    final scheme = Theme.of(context).colorScheme;
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(playing),
        size: size * 0.52,
      ),
    );
    final button = filled
        ? IconButton.filled(
            onPressed: () => ref.read(playerEngineProvider).togglePlayPause(),
            tooltip: playing ? l10n.playerPause : l10n.playerPlay,
            style: IconButton.styleFrom(minimumSize: Size.square(size)),
            icon: icon,
          )
        : IconButton(
            onPressed: () => ref.read(playerEngineProvider).togglePlayPause(),
            tooltip: playing ? l10n.playerPause : l10n.playerPlay,
            style: IconButton.styleFrom(minimumSize: Size.square(size)),
            icon: icon,
          );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          button,
          if (buffering)
            IgnorePointer(
              child: SizedBox.square(
                dimension: size - 4,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: filled ? scheme.onPrimary.withValues(alpha: 0.7) : scheme.primary,
                  semanticsLabel: l10n.playerLoading,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skip back or forward, with the interval drawn inside the arrow.
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.seconds, required this.forward, required this.onPressed, this.size = 44});

  final int seconds;
  final bool forward;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: forward ? l10n.playerSkipForward(seconds) : l10n.playerSkipBack(seconds),
      iconSize: size,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(flipX: forward, child: const Icon(Icons.replay_rounded)),
          Padding(
            padding: EdgeInsets.only(top: size * 0.11),
            child: Text(
              '$seconds',
              style: theme.textTheme.labelSmall?.copyWith(
                color: IconTheme.of(context).color ?? theme.colorScheme.onSurface,
                fontSize: size * 0.25,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation.weight(700)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Time left at the current speed, in words.
String timeLeftText(AppLocalizations l10n, Duration left) {
  final minutes = left.inMinutes;
  final hours = minutes ~/ 60;
  final text = hours == 0
      ? (left.inSeconds < 60 && left > Duration.zero ? l10n.durationMinutes(1) : l10n.durationMinutes(minutes))
      : (minutes % 60 == 0
            ? l10n.durationHours(hours)
            : l10n.durationHoursMinutes(l10n.durationHours(hours), l10n.durationMinutes(minutes % 60)));
  return text;
}

/// Book time to real time at [speed].
Duration atSpeed(Duration bookTime, double speed) =>
    Duration(milliseconds: (bookTime.inMilliseconds / speed).round().clamp(0, 1 << 52));

/// Opens the book page for what is playing.
String? bookLocation(PlayerSnapshot s) => s.now == null ? null : AppRoutes.book(s.now!.ref, base: AppRoutes.home);
