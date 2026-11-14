// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

package com.affluentlabs.earloom

import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Free space for the Downloads screen's storage bar
// (lib/features/downloads/data/device_storage.dart). Backup exclusion is an
// iOS concern: on Android the backup rules in res/xml keep downloads out.
class StorageChannel(messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "com.affluentlabs.earloom/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(null)
                    } else {
                        try {
                            result.success(StatFs(path).availableBytes)
                        } catch (e: IllegalArgumentException) {
                            result.success(null)
                        }
                    }
                }
                "excludeFromBackup" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
