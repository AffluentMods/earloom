# Apple-only build steps

Scripts that only make sense on the Mac (archive, export, signing) live here, so everything else in `tool/` stays cross-platform.

- `release_ios.sh`: the obfuscated release IPA. Run it yourself on the Mac (signing needs your keychain).

## Signing team

The team ID is not in the Xcode project, because this repo is public. Each Mac keeps it in `ios/Flutter/Signing.xcconfig`, which is git-ignored:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

`ios/Flutter/Debug.xcconfig` and `Release.xcconfig` include that file, and both the Runner and NowPlayingWidget targets build on them, so one line signs both. Do not pick the team in Xcode's Signing & Capabilities tab: Xcode then writes the team ID into `project.pbxproj`, which is committed.
