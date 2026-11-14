// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/ui/cover_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Answers every cover request with 404, so covers show their placeholder.
class _NoNetwork extends FileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async =>
      throw HttpExceptionWithStatus(404, 'covers are offline in tests', uri: Uri.parse(url));
}

/// Points the cover cache at memory and no network: widget tests have no
/// disk cache plugin and must never reach a server.
void useOfflineCoverCache() {
  CoverCache.manager = CacheManager(
    Config('test-covers', repo: NonStoringObjectProvider(), fileSystem: MemoryCacheSystem(), fileService: _NoNetwork()),
  );
}
