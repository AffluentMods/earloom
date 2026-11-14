// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import ActivityKit
import Foundation

/// The sleep timer Live Activity. This file belongs to both the Runner target
/// and the NowPlayingWidget extension target (ios/NowPlayingWidget/README.md),
/// so the app and the widget agree on the shape.
struct SleepTimerAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// When the timer pauses playback, while it counts down.
    var endsAt: Date
    /// Paused playback stops the countdown; the remaining time is shown still.
    var paused: Bool
    var remainingSeconds: Int
  }

  var title: String
}
