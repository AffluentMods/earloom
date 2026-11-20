# Apple-only build steps

Scripts that only make sense on the Mac (archive, export, signing) live here, so everything else in `tool/` stays cross-platform.

- `profiles.rb`: makes and installs the two App Store provisioning profiles, one for the app and one for its widget.
- `build_ipa.sh`: the signed, obfuscated release IPA, built from a clean clone of the commit the checkout is on.

Both are run by the person who holds the signing keys, on the Mac. Neither prints or copies a key, a certificate or the team ID.

## Before the first release

1. The identifiers on developer.apple.com: see `tool/release_checklist.md` (first release) and `ios/NowPlayingWidget/README.md`.
2. An Apple Distribution certificate in the login keychain of the Mac.
3. An App Store Connect API key for the team, saved as `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`. The key ID and the issuer ID are shown where the key was made (App Store Connect, Users and Access, Integrations).
4. The signing team in `ios/Flutter/Signing.xcconfig` (see below).
5. A Ruby 3 with the `xcodeproj` gem (`gem install xcodeproj`). The Ruby 2.6 that comes with macOS is too old; Homebrew's is in `/opt/homebrew/opt/ruby/bin`.
6. The two profiles:

   ```
   SSL_CERT_FILE=/etc/ssl/cert.pem /opt/homebrew/opt/ruby/bin/ruby tool/ios/profiles.rb <key id> <issuer id>
   ```

   It ends with `DONE: both profiles are installed.`, or it says which capability is missing on which App ID. The profiles end when the distribution certificate does: after renewing the certificate, or after changing a capability, run it again.

## Every release

On the Mac, with the release commit pushed and checked out, in one terminal or SSH session:

```
security unlock-keychain ~/Library/Keychains/login.keychain-db && zsh tool/ios/build_ipa.sh
xcrun altool --upload-app --type ios -f ~/Desktop/Earloom-<version>.ipa --apiKey <key id> --apiIssuer <issuer id>
```

The keychain has to be unlocked in the same session that signs: an unlock made anywhere else does not count for codesign. That is why the first line is one command.

`build_ipa.sh` takes the version from `pubspec.yaml` and builds the commit the checkout is on, as it is on `origin`. It checks the profiles, compiles, archives and exports, and then looks inside the IPA: the version of the app and of the widget, what it was signed with, and that no file names the Mac user's home folder. It ends with `DONE:`, the path of the IPA on the Desktop and its SHA-256, and it deletes its build folders in `/tmp`.

`altool` ends with `UPLOAD SUCCEEDED`. The build number has to be higher than that of every build uploaded before.

The symbols that make crash reports readable (the Dart symbols and the dSYMs) go to `~/earloom-releases/<version>+<build>/`, outside the repository. Keep them with the release and back them up.

`REHEARSE=1 zsh tool/ios/build_ipa.sh` does everything up to the archive without signing. It needs no keychain and no profiles, and it leaves the compiled clone in `/tmp` for the signed run of the same commit.

## Why it works this way

- A clean clone in `/tmp`: the release is exactly one public commit. The pub cache and Xcode's DerivedData are in `/tmp` too, so no compiled file carries a `/Users/<name>/` path.
- Profiles through the API and manual signing: Xcode's automatic provisioning needs an Apple ID signed in to Xcode on the build Mac. The project in the repository keeps automatic signing for everyday work. The manual settings are written into the clone only, for the Release configuration of the app and the widget. No signing setting goes on the `xcodebuild` command line, because there it would reach every target, the plugins included.

## Signing team

The team ID is not in the Xcode project, because this repo is public. Each Mac keeps it in `ios/Flutter/Signing.xcconfig`, which is git-ignored:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

`ios/Flutter/Debug.xcconfig` and `Release.xcconfig` include that file, and both the Runner and NowPlayingWidget targets build on them, so one line signs both. Do not pick the team in Xcode's Signing & Capabilities tab: Xcode then writes the team ID into `project.pbxproj`, which is committed.
