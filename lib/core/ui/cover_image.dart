// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

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
/// a palette background, a generated placeholder (initials on a gradient
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

  /// Server covers are requested pre-sized from a few buckets, so the cache
  /// stays small and no list cell ever downloads a full-resolution original.
  static int bucketFor(double logicalSize, double pixelRatio) {
    final px = logicalSize * pixelRatio;
    for (final bucket in const [128, 256, 512, 1024]) {
      if (px <= bucket) return bucket;
    }
    return 1024;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final placeholder = _Placeholder(title: title, size: size);
    final Widget image = switch (source) {
      FileCover(:final path) => Image.file(
        File(path),
        fit: BoxFit.contain,
        cacheWidth: (size * pixelRatio).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
      NetworkCover(:final itemCoverUrl, :final cacheKey, :final headers) => () {
        final width = bucketFor(size, pixelRatio);
        return CachedNetworkImage(
          imageUrl: itemCoverUrl.replace(queryParameters: {'width': '$width', 'format': 'webp'}).toString(),
          cacheKey: '$cacheKey-$width',
          cacheManager: CoverCache.manager,
          httpHeaders: headers,
          fit: BoxFit.contain,
          fadeInDuration: Motion.fast,
          placeholder: (_, _) => ColoredBox(color: scheme.surfaceContainerHigh),
          errorWidget: (_, _, _) => placeholder,
        );
      }(),
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
