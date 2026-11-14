// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Download progress notifications (background_downloader).
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Folder picking for imports (lib/features/local_library).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FolderAccessPlugin") {
      FolderAccessPlugin.register(with: registrar)
    }
    // Free space and iCloud backup exclusion for downloads
    // (lib/features/downloads/data/device_storage.dart). Kept in this file
    // so the Xcode project needs no new source file.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EarloomStorage") {
      let channel = FlutterMethodChannel(
        name: "com.affluentlabs.earloom/storage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any]
        guard let path = args?["path"] as? String else {
          result(nil)
          return
        }
        var url = URL(fileURLWithPath: path)
        switch call.method {
        case "freeBytes":
          let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          if let free = values?.volumeAvailableCapacityForImportantUsage {
            result(NSNumber(value: free))
          } else {
            result(nil)
          }
        case "excludeFromBackup":
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try? url.setResourceValues(values)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
