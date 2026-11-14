// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// File types the importer accepts, by lower case extension (without dot).
abstract final class AudioFormats {
  static const mimeTypes = <String, String>{
    'mp3': 'audio/mpeg',
    'm4b': 'audio/mp4',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'wav': 'audio/wav',
  };

  static Set<String> get extensions => mimeTypes.keys.toSet();

  /// Containers that can hold a whole book with embedded chapters.
  static const chapterContainers = {'m4b', 'm4a'};

  static const imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  /// Base names (lower case, no extension) that mark a folder's cover image.
  static const preferredCoverNames = ['cover', 'folder', 'front', 'albumart', 'poster', 'album'];

  /// The lower case extension of [name], without the dot, or '' if none.
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// [name] without its extension.
  static String stemOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static bool isAudio(String name) => mimeTypes.containsKey(extensionOf(name));

  static bool isImage(String name) => imageExtensions.contains(extensionOf(name));

  /// Image extension to use for a cover with this MIME type, or null when it
  /// is not an image the app can show.
  static String? imageExtensionForMime(String mime) {
    return switch (mime.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };
  }

  /// Sniffs the image type from its first bytes. Null if it is not JPEG, PNG
  /// or WebP.
  static String? sniffImageExtension(List<int> head) {
    if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return 'jpg';
    if (head.length >= 8 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47 &&
        head[4] == 0x0D &&
        head[5] == 0x0A &&
        head[6] == 0x1A &&
        head[7] == 0x0A) {
      return 'png';
    }
    if (head.length >= 12 &&
        head[0] == 0x52 &&
        head[1] == 0x49 &&
        head[2] == 0x46 &&
        head[3] == 0x46 &&
        head[8] == 0x57 &&
        head[9] == 0x45 &&
        head[10] == 0x42 &&
        head[11] == 0x50) {
      return 'webp';
    }
    return null;
  }

  /// Names that are never user content: macOS resource forks ("._01.mp3"),
  /// hidden files and system folders.
  static bool isJunk(String name) {
    if (name.isEmpty || name.startsWith('.')) return true;
    final lower = name.toLowerCase();
    return lower == '__macosx' || lower == 'thumbs.db' || lower == 'desktop.ini';
  }
}
