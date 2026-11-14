// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import ActivityKit
import Flutter
import Foundation

/// Starts, updates and ends the sleep timer Live Activity when the app asks
/// (lib/platform/native_bridge.dart). Local updates only, no push tokens.
enum SleepActivity {
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "sleepActivityShow":
      let title = args["title"] as? String ?? ""
      let remaining = (args["remainingSeconds"] as? NSNumber)?.intValue ?? 0
      let paused = (args["paused"] as? NSNumber)?.boolValue ?? false
      Task {
        await show(title: title, remaining: remaining, paused: paused)
        result(nil)
      }
    case "sleepActivityEnd":
      Task {
        await endAll()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func show(title: String, remaining: Int, paused: Bool) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = SleepTimerAttributes.ContentState(
      endsAt: Date().addingTimeInterval(TimeInterval(remaining)),
      paused: paused,
      remainingSeconds: remaining
    )
    let content = ActivityContent(state: state, staleDate: state.endsAt.addingTimeInterval(60))
    if let current = Activity<SleepTimerAttributes>.activities.first {
      await current.update(content)
      return
    }
    do {
      _ = try Activity.request(attributes: SleepTimerAttributes(title: title), content: content, pushType: nil)
    } catch {
      // Live Activities turned off for the app: the in-app timer still runs.
    }
  }

  /// Also called at launch, so an activity left over from a killed app goes.
  static func endAll() async {
    for activity in Activity<SleepTimerAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
