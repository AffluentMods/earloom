// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'audio_formats.dart';
import 'import_source.dart';

/// The system pickers, behind an interface so the import screen can be
/// tested without them.
abstract interface class ImportPicker {
  /// Lets the user pick audio files (and optionally a cover image). Null when
  /// they cancel. [onPreparing] is called while the system copies large
  /// files out of a cloud or another app before handing them over.
  Future<ImportSelection?> pickFiles({void Function()? onPreparing});

  /// Lets the user pick a folder. Null when they cancel.
  Future<ImportSelection?> pickFolder();

  /// Lets the user pick a cover image. Returns a readable path, or null.
  Future<String?> pickImage();
}

/// The real pickers.
///
/// - Files: `file_picker`, which hands over copies in the app's cache on both
///   platforms. The importer moves those instead of copying them again.
/// - Folder on Android: `file_picker` returns a Storage Access Framework tree
///   (no storage permission needed, none requested); the files are listed
///   and read through [SafChannel].
/// - Folder on iOS: [FolderAccessChannel] presents the document picker and
///   keeps the security-scoped folder open until the import is done.
final class PlatformImportPicker implements ImportPicker {
  const PlatformImportPicker();

  @override
  Future<ImportSelection?> pickFiles({void Function()? onPreparing}) async {
    final files = await FilePicker.pickFiles(
      // Android's picker filters by MIME type, and many file providers label
      // .m4b and .opus as generic data, so it shows everything and the
      // importer skips what it cannot play. iOS filters by extension.
      type: Platform.isIOS ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isIOS ? [...AudioFormats.extensions, ...AudioFormats.imageExtensions] : null,
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) onPreparing?.call();
      },
    );
    if (files.isEmpty) return null;
    final sources = <ImportSourceFile>[];
    for (final picked in files) {
      final path = picked.path;
      if (path == null) continue;
      final file = File(path);
      sources.add(IoImportFile(file, segments: [picked.name], size: await file.length(), isTemporaryCopy: true));
    }
    return PickedFiles(sources, onDone: FilePicker.clearTemporaryFiles);
  }

  @override
  Future<ImportSelection?> pickFolder() async {
    if (Platform.isAndroid) {
      final treeUri = await FilePicker.getDirectoryPath(
        // Read only, and only for now: the import copies everything, so the
        // app never needs to come back to the folder.
        androidOptions: const FilePickerAndroidOptions(safOptions: AndroidSAFOptions(persistGrant: false)),
      );
      if (treeUri == null) return null;
      final listing = await const SafChannel().list(treeUri);
      return PickedFolder(listing.name, listing.files);
    }
    if (Platform.isIOS) {
      final path = await const FolderAccessChannel().pick();
      if (path == null) return null;
      try {
        return PickedFolder(
          p.basename(path),
          await listFolder(Directory(path)),
          onDone: () => const FolderAccessChannel().release(path),
        );
      } on Object {
        await const FolderAccessChannel().release(path);
        rethrow;
      }
    }
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return null;
    return PickedFolder(p.basename(path), await listFolder(Directory(path)));
  }

  @override
  Future<String?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
      // HEIC photos come back as JPEG, which every platform can show.
      darwinOptions: const DarwinOptions(assetRepresentationMode: DarwinAssetRepresentationMode.compatible),
    );
    return file?.path;
  }
}

/// Lists every file below [root] with `dart:io`, as import sources.
Future<List<ImportSourceFile>> listFolder(Directory root) async {
  final files = <ImportSourceFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = p.split(p.relative(entity.path, from: root.path));
    // iCloud placeholders for files that are not on the phone yet.
    if (segments.last.startsWith('.') && segments.last.endsWith('.icloud')) {
      throw const FolderNotDownloaded();
    }
    files.add(IoImportFile(entity, segments: segments, size: await entity.length()));
  }
  return files;
}

/// The picked folder holds files that are still only in iCloud.
final class FolderNotDownloaded implements Exception {
  const FolderNotDownloaded();

  @override
  String toString() => 'FolderNotDownloaded: some files are not downloaded to this device yet';
}

/// Reads an Android Storage Access Framework folder through the app's own
/// method channel (android/app/src/main/kotlin/.../SafChannel.kt): listing,
/// then streaming each document in chunks, so nothing needs a file path or a
/// storage permission.
final class SafChannel {
  const SafChannel();

  static const _channel = MethodChannel('com.affluentlabs.earloom/saf');
  static const chunkSize = 1024 * 1024;

  Future<({String name, List<ImportSourceFile> files})> list(String treeUri) async {
    final result = await _channel.invokeMapMethod<String, Object?>('list', {'treeUri': treeUri});
    if (result == null) throw PlatformException(code: 'unreadable', message: 'The folder could not be listed');
    final entries = (result['files'] as List<Object?>? ?? const []).whereType<Map<Object?, Object?>>();
    return (
      name: result['name'] as String? ?? '',
      files: [
        for (final entry in entries)
          SafImportFile(
            uri: entry['uri']! as String,
            segments: [for (final s in entry['segments']! as List<Object?>) s! as String],
            size: (entry['size'] as int?) ?? 0,
          ),
      ],
    );
  }

  Future<int> open(String uri) async => (await _channel.invokeMethod<int>('open', {'uri': uri}))!;

  /// Up to [max] bytes; empty at the end.
  Future<Uint8List> read(int handle, int max) async =>
      (await _channel.invokeMethod<Uint8List>('read', {'handle': handle, 'max': max})) ?? Uint8List(0);

  Future<void> skip(int handle, int count) => _channel.invokeMethod<void>('skip', {'handle': handle, 'count': count});

  Future<void> close(int handle) => _channel.invokeMethod<void>('close', {'handle': handle});
}

/// A document inside a picked Android folder.
final class SafImportFile extends ImportSourceFile {
  SafImportFile({required this.uri, required this.segments, required this.size});

  final String uri;
  @override
  final List<String> segments;
  @override
  final int size;

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    const channel = SafChannel();
    final handle = await channel.open(uri);
    try {
      var position = start ?? 0;
      if (position > 0) await channel.skip(handle, position);
      while (end == null || position < end) {
        final want = end == null ? SafChannel.chunkSize : (end - position).clamp(0, SafChannel.chunkSize);
        final chunk = await channel.read(handle, want);
        if (chunk.isEmpty) break;
        position += chunk.length;
        yield chunk;
      }
    } finally {
      await channel.close(handle);
    }
  }
}

/// Picks a folder on iOS and holds its security scope open
/// (ios/Runner/FolderAccessPlugin.swift). `file_picker` returns only the
/// folder's path and never starts access, so its files cannot be read.
final class FolderAccessChannel {
  const FolderAccessChannel();

  static const _channel = MethodChannel('com.affluentlabs.earloom/folder_access');

  /// The picked folder's path, readable until [release]. Null if cancelled.
  Future<String?> pick() => _channel.invokeMethod<String>('pick');

  Future<void> release(String path) => _channel.invokeMethod<void>('release', {'path': path});
}
