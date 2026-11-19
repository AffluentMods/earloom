# Now Playing widget and sleep timer Live Activity

`NowPlayingWidget.swift` is the whole WidgetKit extension: the Now Playing
widget (home screen small and medium, lock screen rectangular and circular)
and the sleep timer Live Activity. The app side already writes the data
(`lib/platform/widget_bridge.dart`) and starts the activity
(`ios/Runner/SleepActivity.swift`).

The `NowPlayingWidget` extension target is already in
`ios/Runner.xcodeproj`: it builds `NowPlayingWidget.swift` and
`ios/Runner/SleepTimerAttributes.swift`, uses `Info.plist` and
`NowPlayingWidget.entitlements` from this folder, and is embedded in the app
(the "Embed Foundation Extensions" phase sits before Flutter's "Thin Binary"
script, which avoids Xcode's build cycle error).

Entitlements in the repo:

- App (`ios/Runner/Runner.entitlements`): CarPlay Audio
  (`com.apple.developer.carplay-audio`) and the App Group
  `group.com.affluentlabs.earloom`.
- Widget (`NowPlayingWidget.entitlements`): the same App Group.

What the Mac still needs, once, because signing uses the owner's account:

1. In the Apple developer site, Identifiers: make sure the App Group
   `group.com.affluentlabs.earloom` exists, the App ID
   `com.affluentlabs.earloom` has App Groups (with that group) and CarPlay
   Audio, and the App ID `com.affluentlabs.earloom.NowPlayingWidget` exists
   with App Groups (same group).
2. Put the team ID in `ios/Flutter/Signing.xcconfig` (git-ignored, see
   `tool/ios/README.md`); it signs both the Runner and NowPlayingWidget
   targets. Do not pick the team in Xcode, which writes it into the
   committed project file. Open `ios/Runner.xcworkspace` and check each
   target's Signing & Capabilities: Xcode shows the team and the
   capabilities from the entitlements files; fix anything it marks red.
3. `flutter run` on an iPhone: add the widget, play a book, start a sleep
   timer and lock the phone. Then the CarPlay Simulator (Xcode > Open
   Developer Tool > Simulator, I/O > External Displays > CarPlay).
