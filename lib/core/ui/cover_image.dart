// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// The disk cache for server covers and author photos: its own store, so
/// covers never push other images out, capped by count (about 300 MB at
/// the sizes the app requests), least recently used first out.
abstract final class CoverCache {
  static const key = 'earloomCovers';

  /// Replaced in tests, which have no disk cache plugin and no network.
  static BaseCacheManager manager = CacheManager(
    Config(key, stalePeriod: const Duration(days: 90), maxNrOfCacheObjects: 3000),
  );

  /// The general image store. Builds up to 1.0.0 (2) kept two kinds of
  /// cover there: the one the home screen widget shows, and the small
  /// copies colors are picked from. Nothing is written to it any more; it
  /// is only emptied, for people who update. Null in tests.
  static BaseCacheManager? older = DefaultCacheManager();

  /// Deletes every saved cover.
  static Future<void> clear() async {
    await manager.emptyCache();
    await older?.emptyCache();
  }
}

/// Where a cover comes from.
sealed class CoverSource {
  const CoverSource();
}

/// A file on this phone: imported books, downloaded books.
final class FileCover extends CoverSource {
  const FileCover(this.path);
  final String path;
}

/// An Audiobookshelf cover. The cover endpoint needs no token
/// (docs/abs-api.md section 8); custom reverse-proxy headers still apply.
final class NetworkCover extends CoverSource {
  const NetworkCover({required this.itemCoverUrl, required this.cacheKey, this.headers = const {}});

  /// `<server>/api/items/<id>/cover`, without query parameters.
  final Uri itemCoverUrl;

  /// Changes whenever the cover changes (item id plus updatedAt).
  final String cacheKey;
  final Map<String, String> headers;
}

/// A book cover: never stretched, rounded, square-ish covers letterboxed on
/// a soft, blurred copy of themselves, a generated placeholder (initials on a gradient
/// from the theme) when there is no cover or it fails to load.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.source,
    required this.title,
    required this.size,
    this.radius = Radii.cover,
    this.heroTag,
    this.shadow = false,
  });

  final CoverSource? source;

  /// For the placeholder initials and the semantics label.
  final String title;

  /// Logical size of the square the cover sits in.
  final double size;
  final double radius;
  final Object? heroTag;
  final bool shadow;

  static const _buckets = [128, 256, 512, 1024];

  /// Server covers are requested pre-sized from a few buckets, so the cache
  /// stays small and no list cell ever downloads a full-resolution original.
  static int bucketFor(double logicalSize, double pixelRatio) {
    final px = logicalSize * pixelRatio;
    for (final bucket in _buckets) {
      if (px <= bucket) return bucket;
    }
    return _buckets.last;
  }

  /// The next smaller bucket, or null below the smallest.
  static int? bucketBelow(int bucket) {
    final i = _buckets.indexOf(bucket);
    return i > 0 ? _buckets[i - 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final placeholder = _Placeholder(title: title, size: size);
    final Widget image = switch (source) {
      FileCover(:final path) => Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(
            image: Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: _Backdrop.pixels,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Image.file(
            File(path),
            fit: BoxFit.contain,
            cacheWidth: (size * pixelRatio).round(),
            errorBuilder: (_, _, _) => placeholder,
          ),
        ],
      ),
      final NetworkCover cover => _NetworkCoverImage(
        cover: cover,
        bucket: bucketFor(size, pixelRatio),
        placeholder: placeholder,
      ),
      null => placeholder,
    };
    Widget cover = Semantics(
      image: true,
      label: title,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.32),
                    blurRadius: size * 0.12,
                    offset: Offset(0, size * 0.05),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: ExcludeSemantics(child: image),
      ),
    );
    if (heroTag != null) cover = Hero(tag: heroTag!, child: cover);
    return cover;
  }
}

/// A server cover that gets over a failed download. One lost request (a
/// busy server, a network blip) used to leave the placeholder on screen for
/// as long as the page stayed open. Now the wanted size is asked for again a
/// few times, further apart each time, and meanwhile the next smaller size
/// shows, which a list has usually cached already. A cover the server says
/// it does not have (404) is not asked for again.
class _NetworkCoverImage extends StatefulWidget {
  const _NetworkCoverImage({required this.cover, required this.bucket, required this.placeholder});

  final NetworkCover cover;

  /// The pre-sized width to ask the server for.
  final int bucket;

  /// Shown when no size of the cover can be had.
  final Widget placeholder;

  /// How long to wait before each new try.
  static const retryAfter = [Duration(seconds: 2), Duration(seconds: 6), Duration(seconds: 20)];

  @override
  State<_NetworkCoverImage> createState() => _NetworkCoverImageState();
}

class _NetworkCoverImageState extends State<_NetworkCoverImage> {
  int _tries = 0;
  Timer? _retry;

  @override
  void didUpdateWidget(_NetworkCoverImage old) {
    super.didUpdateWidget(old);
    final cover = widget.cover, before = old.cover;
    if (cover.cacheKey != before.cacheKey || cover.itemCoverUrl != before.itemCoverUrl || widget.bucket != old.bucket) {
      _retry?.cancel();
      _retry = null;
      _tries = 0;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _tryAgainLater() {
    if (_retry != null || _tries >= _NetworkCoverImage.retryAfter.length) return;
    _retry = Timer(_NetworkCoverImage.retryAfter[_tries], () {
      _retry = null;
      if (mounted) setState(() => _tries++);
    });
  }

  String _url(int width) =>
      widget.cover.itemCoverUrl.replace(queryParameters: {'width': '$width', 'format': 'webp'}).toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = widget.cover;
    final bucket = widget.bucket;
    final smaller = CoverImage.bucketBelow(bucket);
    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(
          // A new key makes a new image, which is what asks the server again.
          image: CachedNetworkImage(
            key: ValueKey('backdrop-$_tries'),
            imageUrl: _url(bucket),
            cacheKey: '${cover.cacheKey}-$bucket',
            cacheManager: CoverCache.manager,
            httpHeaders: cover.headers,
            memCacheWidth: _Backdrop.pixels,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            fadeInDuration: Motion.fast,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        CachedNetworkImage(
          key: ValueKey('cover-$_tries'),
          imageUrl: _url(bucket),
          cacheKey: '${cover.cacheKey}-$bucket',
          cacheManager: CoverCache.manager,
          httpHeaders: cover.headers,
          fit: BoxFit.contain,
          fadeInDuration: Motion.fast,
          placeholder: (_, _) => ColoredBox(color: scheme.surfaceContainerHigh),
          errorWidget: (_, _, error) {
            if (error is HttpExceptionWithStatus && error.statusCode == 404) return widget.placeholder;
            _tryAgainLater();
            if (smaller == null) return widget.placeholder;
            return CachedNetworkImage(
              imageUrl: _url(smaller),
              cacheKey: '${cover.cacheKey}-$smaller',
              cacheManager: CoverCache.manager,
              httpHeaders: cover.headers,
              fit: BoxFit.contain,
              fadeInDuration: Motion.fast,
              placeholder: (_, _) => ColoredBox(color: scheme.surfaceContainerHigh),
              errorWidget: (_, _, _) => widget.placeholder,
            );
          },
        ),
      ],
    );
  }
}

/// What shows beside a cover that is not square: the same cover decoded a
/// few pixels wide and stretched, which blurs it for free, under a light
/// scrim so the real cover keeps its edges. Square covers hide it.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.image});

  final Widget image;

  /// Width the backdrop is decoded at. Tiny on purpose.
  static const pixels = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          ColoredBox(color: scheme.scrim.withValues(alpha: 0.22)),
        ],
      ),
    );
  }
}

/// Initials on a gradient picked from the title, from theme colors only.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.size});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (background, foreground) = pairs[title.hashCode.abs() % pairs.length];
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background, Color.lerp(background, scheme.surface, 0.35)!],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: foreground, fontSize: size * 0.32),
        ),
      ),
    );
  }
}
