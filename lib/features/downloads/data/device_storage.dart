// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter/services.dart';

/// Free space and iCloud backup exclusion, through the app's own small
/// channel (`StorageChannel.kt` on Android, `AppDelegate.swift` on iOS).
/// Every call fails soft: no answer means "unknown", never an error.
class DeviceStorage {
  const DeviceStorage();

  static const _channel = MethodChannel('com.affluentlabs.earloom/storage');

  /// Bytes free for the app on the volume holding [path], or null.
  Future<int?> freeBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } on Object {
      return null;
    }
  }

  /// Keeps [path] (a folder and everything in it) out of iCloud backups.
  /// Nothing to do on Android: app-specific files are not in its backups
  /// beyond the auto-backup quota, which skips large files.
  Future<void> excludeFromBackup(String path) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('excludeFromBackup', {'path': path});
    } on Object {
      // The downloader still marks each audio file.
    }
  }
}
