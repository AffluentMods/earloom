// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

package com.affluentlabs.earloom

import android.content.Context
import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the system's audio output picker (speaker, headphones, Bluetooth,
 * Cast) from the Now Playing output button
 * (lib/features/player/ui/output_button.dart).
 */
class OutputChannel(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "com.affluentlabs.earloom/output").setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> result.success(show())
                else -> result.notImplemented()
            }
        }
    }

    private fun show(): Boolean {
        if (Build.VERSION.SDK_INT >= 34) {
            return MediaRouter2.getInstance(context).showSystemOutputSwitcher()
        }
        if (Build.VERSION.SDK_INT >= 30) {
            // Android 11 to 13: the System UI media output dialog.
            val intent = Intent("com.android.systemui.action.LAUNCH_MEDIA_OUTPUT_DIALOG")
                .setPackage("com.android.systemui")
                .putExtra("package_name", context.packageName)
            context.sendBroadcast(intent)
            return true
        }
        return false
    }
}
