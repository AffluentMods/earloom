// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import Flutter
import Foundation

/// The one method channel between native iOS features (CarPlay, Siri and
/// Shortcuts, Live Activities) and the app (lib/platform/native_bridge.dart).
/// Calls made before the Flutter engine is ready wait and go out once it is.
final class EarloomBridge {
  static let shared = EarloomBridge()
  static let channelName = "com.affluentlabs.earloom/native"

  private var channel: FlutterMethodChannel?
  private var pending: [(method: String, arguments: Any?, done: ((Any?) -> Void)?)] = []

  var isAttached: Bool { channel != nil }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: EarloomBridge.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      SleepActivity.handle(call, result)
    }
    self.channel = channel
    let queued = pending
    pending.removeAll()
    for call in queued {
      send(call.method, call.arguments, call.done)
    }
  }

  /// Calls the app. [done] receives the result, or nil when the call failed.
  func send(_ method: String, _ arguments: Any? = nil, _ done: ((Any?) -> Void)? = nil) {
    DispatchQueue.main.async {
      guard let channel = self.channel else {
        self.pending.append((method, arguments, done))
        return
      }
      channel.invokeMethod(method, arguments: arguments) { result in
        if result is FlutterError || (result as? NSObject) === FlutterMethodNotImplemented {
          done?(nil)
        } else {
          done?(result)
        }
      }
    }
  }
}
