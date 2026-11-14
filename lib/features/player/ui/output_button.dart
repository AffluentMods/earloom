// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// Opens the system's picker for where audio plays: speaker, headphones,
/// Bluetooth, AirPlay or Cast. Hidden where the system has no such picker.
class OutputButton extends StatelessWidget {
  const OutputButton({super.key});

  static const _android = MethodChannel('com.affluentlabs.earloom/output');
  static const _ios = MethodChannel('com.affluentlabs.earloom/native');

  static Future<bool> show() async {
    try {
      final shown = Platform.isIOS
          ? await _ios.invokeMethod<bool>('showOutputPicker')
          : await _android.invokeMethod<bool>('show');
      return shown ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) return const SizedBox.shrink();
    return IconButton(
      icon: Icon(Platform.isIOS ? Icons.airplay_rounded : Icons.speaker_group_outlined),
      tooltip: AppLocalizations.of(context).playerOutput,
      onPressed: show,
    );
  }
}
