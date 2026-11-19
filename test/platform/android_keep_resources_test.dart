// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android drawables the Dart code names as strings are found by name at
/// runtime, so the release resource shrinker cannot see them and removes
/// them. Then the playback notification fails to build and nothing reaches
/// the lock screen. Every such name must be in res/raw/keep.xml.
void main() {
  test('every drawable named from Dart is kept in release builds', () {
    final named = <String>{};
    var usesBuiltInControls = false;
    final patterns = [
      RegExp(r"""['"]drawable/([a-z0-9_]+)['"]"""),
      RegExp(r"""AndroidInitializationSettings\(\s*['"]([a-z0-9_]+)['"]"""),
    ];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final pattern in patterns) {
        named.addAll(pattern.allMatches(source).map((m) => m.group(1)!));
      }
      if (RegExp(r'MediaControl\.(play|pause|rewind|fastForward|stop|skipToNext|skipToPrevious)\b').hasMatch(source)) {
        usesBuiltInControls = true;
      }
    }
    expect(named, isNotEmpty, reason: 'the scan found no drawable names at all');

    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    // audio_service's own MediaControl icons are named inside the package.
    if (usesBuiltInControls) {
      expect(keep, contains('@drawable/audio_service_*'), reason: 'MediaControl icons come from audio_service');
    }
    final kept = RegExp('@drawable/([a-z0-9_]+)').allMatches(keep).map((m) => m.group(1)!).toSet();
    expect(named.difference(kept), isEmpty, reason: 'add these to android/app/src/main/res/raw/keep.xml');

    // Any density or format: drawable/x.xml, drawable-xxhdpi/x.png and so on.
    final drawables = Directory('android/app/src/main/res')
        .listSync()
        .whereType<Directory>()
        .where((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('drawable'))
        .expand((d) => d.listSync().whereType<File>())
        .map((f) => f.uri.pathSegments.last.split('.').first)
        .toSet();
    expect(named.difference(drawables), isEmpty, reason: 'named from Dart but no such drawable');
  });
}
