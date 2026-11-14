// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

package com.affluentlabs.earloom

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity shares one Flutter engine with the playback
// service, so audio keeps going when the activity is gone.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Reads folders picked for import (lib/features/local_library).
        SafChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
