# Now Playing widget and sleep timer Live Activity

`NowPlayingWidget.swift` is the whole WidgetKit extension: the Now Playing
widget (home screen small and medium, lock screen rectangular and circular)
and the sleep timer Live Activity. The app side already writes the data
(`lib/platform/widget_bridge.dart`) and starts the activity
(`ios/Runner/SleepActivity.swift`).

The Xcode target is created once, on the Mac:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. File > New > Target > Widget Extension. Product name `NowPlayingWidget`,
   bundle id `com.affluentlabs.earloom.NowPlayingWidget`, tick "Include Live
   Activity", untick "Include Configuration App Intent". Do not activate the
   new scheme.
3. Delete the Swift files Xcode generated in the new group and add this
   folder's `NowPlayingWidget.swift` to the `NowPlayingWidget` target.
4. Add `ios/Runner/SleepTimerAttributes.swift` to the `NowPlayingWidget`
   target too (File inspector > Target Membership), keeping it in Runner.
5. Signing & Capabilities: add the App Group `group.com.affluentlabs.earloom`
   to both the Runner and the NowPlayingWidget targets.
6. Set the extension's deployment target to iOS 17.0, like Runner.
7. `flutter build ios` and run on a phone: add the widget, play a book, start
   a sleep timer and lock the phone.

CarPlay needs the CarPlay audio entitlement once Apple grants it: Signing &
Capabilities > + Capability > CarPlay Audio (`com.apple.developer.carplay-audio`).
The CarPlay scene (`ios/Runner/CarPlaySceneDelegate.swift`) is already in
the app and stays dormant until then.
