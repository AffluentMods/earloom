// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import AVKit
import Flutter
import Foundation
import UIKit

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
      if call.method == "showOutputPicker" {
        result(OutputPicker.show())
        return
      }
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

/// The AirPlay and Bluetooth output picker for the Now Playing output
/// button. AVRoutePickerView has no public "show" call, so a hidden picker
/// gets a tap on its own button.
enum OutputPicker {
  private static var picker: AVRoutePickerView?

  static func show() -> Bool {
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
    else { return false }
    let view = picker ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    view.alpha = 0.01
    view.prioritizesVideoDevices = false
    if view.superview == nil { window.addSubview(view) }
    picker = view
    guard let button = view.subviews.compactMap({ $0 as? UIButton }).first else { return false }
    button.sendActions(for: .touchUpInside)
    return true
  }
}
