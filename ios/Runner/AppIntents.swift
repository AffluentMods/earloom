// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import AppIntents
import Foundation

// Siri, Shortcuts and Spotlight actions (docs/plan/07-phase6-system-integration.md
// 6.6). Each one opens the app and hands the request to the player through
// EarloomBridge, which waits until the app is ready. Phrases mirror
// shortcut* keys in lib/l10n/app_en.arb.

struct ResumeListeningIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume listening"
  static let description = IntentDescription("Plays the book you were listening to.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    EarloomBridge.shared.send("resume")
    return .result()
  }
}

struct AddBookmarkIntent: AppIntent {
  static let title: LocalizedStringResource = "Add bookmark"
  static let description = IntentDescription("Bookmarks the spot you are listening to.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    EarloomBridge.shared.send("bookmark")
    return .result()
  }
}

struct StartSleepTimerIntent: AppIntent {
  static let title: LocalizedStringResource = "Start sleep timer"
  static let description = IntentDescription("Pauses playback after the minutes you choose.")
  static let openAppWhenRun = true

  @Parameter(title: "Minutes", default: 30, inclusiveRange: (1, 240))
  var minutes: Int

  func perform() async throws -> some IntentResult {
    EarloomBridge.shared.send("sleep", ["minutes": minutes])
    return .result()
  }
}

struct EarloomShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ResumeListeningIntent(),
      phrases: ["Resume listening in \(.applicationName)", "Continue my book in \(.applicationName)"],
      shortTitle: "Resume",
      systemImageName: "play.fill"
    )
    AppShortcut(
      intent: AddBookmarkIntent(),
      phrases: ["Add a bookmark in \(.applicationName)"],
      shortTitle: "Add bookmark",
      systemImageName: "bookmark"
    )
    AppShortcut(
      intent: StartSleepTimerIntent(),
      phrases: ["Start a sleep timer in \(.applicationName)"],
      shortTitle: "Sleep timer",
      systemImageName: "moon.zzz"
    )
  }
}
