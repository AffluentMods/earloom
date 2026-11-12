// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Renders the design previews to PNG files in build/screenshots/, for design
// review without a device. Not part of the test suite (the file name does
// not end in _test.dart). Run it from the repo root:
//
//   flutter test tool/screenshots/design_previews.dart
//
// Rendering differs a little between operating systems, so these images are
// for looking at, never for pixel comparison.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:earloom/app/debug/demo_books.dart';
import 'package:earloom/app/debug/design_item_preview.dart';
import 'package:earloom/app/debug/design_player_preview.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/app/theme/cover_scheme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/test_app.dart';

const _phone = Size(412, 915); // A common Android phone, in logical pixels.
const _pixelRatio = 2.0;

void main() {
  setUpAll(loadAppFonts);

  final books = [demoBooks[0], demoBooks[1], demoBooks[3], demoBooks[4], demoBooks[6]];
  final modes = <String, ({Brightness brightness, bool amoled})>{
    'dark': (brightness: Brightness.dark, amoled: false),
    'light': (brightness: Brightness.light, amoled: false),
    'amoled': (brightness: Brightness.dark, amoled: true),
  };

  for (final book in books) {
    for (final mode in modes.entries) {
      for (final screen in ['item', 'player']) {
        final name = '${screen}_${book.id.replaceFirst('demo-', '')}_${mode.key}';
        testWidgets(name, (tester) async {
          tester.view.physicalSize = _phone * _pixelRatio;
          tester.view.devicePixelRatio = _pixelRatio;
          addTearDown(tester.view.reset);
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);

          final cover = FileImage(File(book.coverAsset));
          late ColorScheme scheme;
          await tester.runAsync(() async {
            final seed = await CoverSchemeService.extractSeed(cover);
            scheme = CoverSchemeService.schemeFromSeed(seed, mode.value.brightness, amoled: mode.value.amoled);
            // The previews show the bundled asset: decode it before the frame.
            await precacheImage(book.cover, tester.element(find.byType(View)));
          });

          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.fromScheme(scheme),
                home: screen == 'item' ? DesignItemPreview(book: book) : DesignPlayerPreview(book: book),
              ),
            ),
          );
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pumpAndSettle();

          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: _pixelRatio);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = File('build/screenshots/$name.png');
            await out.create(recursive: true);
            await out.writeAsBytes(bytes!.buffer.asUint8List());
          });
        });
      }
    }
  }
}
