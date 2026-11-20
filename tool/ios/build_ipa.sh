#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Builds, signs and exports the iOS release for App Store Connect, from a
# clean clone of the commit this checkout is on. Always obfuscated.
#
# Run it yourself on the Mac, in ONE terminal or SSH session, after unlocking
# the keychain in that same session (an unlock made anywhere else does not
# count for codesign):
#   security unlock-keychain ~/Library/Keychains/login.keychain-db && zsh tool/ios/build_ipa.sh
# Nothing here opens a key or a certificate: xcodebuild signs with the Apple
# Distribution identity in the keychain and the two App Store profiles that
# tool/ios/profiles.rb installed.
#
#   REHEARSE=1 zsh tool/ios/build_ipa.sh   compiles and archives without signing (no keychain, no IPA)
#
# The steps around it and the reasons are in tool/ios/README.md.
set -e
export LANG=en_US.UTF-8
ROOT=${0:A:h:h:h}

fail() { echo "STOP: $*"; exit 1; }
pb() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

[ "$(uname)" = "Darwin" ] || fail "Run this on the Mac."

# What to build: the version in pubspec.yaml and the commit this checkout is on, as pushed.
FULL=$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)[[:space:]]*$/\1/p' "$ROOT/pubspec.yaml" | head -1)
[ -n "$FULL" ] || fail "pubspec.yaml has no version of the form 1.2.3+4."
VER=${FULL%%+*}
BUILD=${FULL##*+}
COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || fail "$ROOT is not a git checkout."
REPO=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || fail "This checkout has no origin to clone from."

# The Flutter release this repository is built with is the one CI uses. A Mac
# can have another one first on PATH, so the usual folders are tried as well;
# EARLOOM_FLUTTER can name the bin folder of the right one.
WANT=$(sed -nE 's/^[[:space:]]*FLUTTER_VERSION:[[:space:]]*([0-9]+\.[0-9]+)\..*/\1/p' "$ROOT/.github/workflows/ci.yml" | head -1)
[ -n "$WANT" ] || fail "Could not read FLUTTER_VERSION from .github/workflows/ci.yml."
ON_PATH=$(command -v flutter 2>/dev/null || true)
FLUTTER_BIN=""
for d in "$EARLOOM_FLUTTER" "${ON_PATH:h}" "$HOME"/flutter-$WANT*/bin(N) "$HOME/flutter/bin"; do
  [ -n "$d" ] && [ -x "$d/flutter" ] || continue
  if "$d/flutter" --version 2>/dev/null | grep -m1 '^Flutter ' | grep -q "^Flutter $WANT\."; then FLUTTER_BIN=$d; break; fi
done
[ -n "$FLUTTER_BIN" ] || fail "No Flutter $WANT.x found. Set EARLOOM_FLUTTER to the bin folder of one."
export PATH=$FLUTTER_BIN:$PATH
# A pub cache outside the home folder, so no compiled file names /Users/<this Mac's user>/.
export PUB_CACHE=/tmp/earloom_pubcache

# The manual signing step needs a Ruby with the xcodeproj gem.
ON_PATH=$(command -v ruby 2>/dev/null || true)
RUBY=""
for r in "$EARLOOM_RUBY" /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby "$ON_PATH"; do
  [ -n "$r" ] && [ -x "$r" ] || continue
  if "$r" -e 'require "xcodeproj"' 2>/dev/null; then RUBY=$r; break; fi
done
[ -n "$RUBY" ] || fail "No Ruby with the xcodeproj gem found (gem install xcodeproj, or set EARLOOM_RUBY)."

APP_ID=com.affluentlabs.earloom
WIDGET_ID=com.affluentlabs.earloom.NowPlayingWidget
GROUP=group.com.affluentlabs.earloom
APP_PROFILE="Earloom AppStore"
WIDGET_PROFILE="Earloom Widget AppStore"
SIGNING=$ROOT/ios/Flutter/Signing.xcconfig
SRC=/tmp/earloom-rel$VER
WORK=/tmp/earloom_ios_$VER
IPA_OUT=$HOME/Desktop/Earloom-$VER.ipa
# Symbols for reading crash reports later: kept outside the repository, never committed.
KEEP=${EARLOOM_SYMBOLS:-$HOME/earloom-releases}/$VER+$BUILD
SYMBOLS=build/debug-symbols/$VER+$BUILD/ios

echo "== Earloom $VER ($BUILD), commit ${COMMIT[1,7]}, $("$FLUTTER_BIN/flutter" --version 2>/dev/null | grep -m1 '^Flutter ' | cut -d' ' -f1-2)"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || echo "   NOTE: this checkout has changes that are not committed. They are not in the build."

[ -f "$SIGNING" ] || fail "No $SIGNING (one line: DEVELOPMENT_TEAM = the team ID). See tool/ios/README.md."
TEAM=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' "$SIGNING" | head -1)
[ -n "$TEAM" ] || fail "No DEVELOPMENT_TEAM line in $SIGNING."

rm -rf "$WORK"; mkdir -p "$WORK"

# Finds the newest installed provisioning profile with this name and checks that it fits this target.
# $1 profile name, $2 bundle id, $3 "carplay" when the target needs CarPlay Audio.
check_profile() {
  local name=$1 id=$2 want=$3 f p="$WORK/profile.plist" best="" bestexp="" exp
  for f in "$HOME/Library/MobileDevice/Provisioning Profiles"/*(N) "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*(N); do
    security cms -D -i "$f" > "$p" 2>/dev/null || continue
    [ "$(pb "$p" Name)" = "$name" ] || continue
    exp=$(plutil -extract ExpirationDate raw -o - "$p" 2>/dev/null)
    if [[ -z "$best" || "$exp" > "$bestexp" ]]; then best=$f; bestexp=$exp; fi
  done
  [ -n "$best" ] || fail "The profile \"$name\" is not installed on this Mac. Run tool/ios/profiles.rb first."
  security cms -D -i "$best" > "$p" 2>/dev/null
  [[ "$bestexp" > "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || fail "The profile \"$name\" expired on $bestexp. Run tool/ios/profiles.rb again."
  [ "$(pb "$p" Entitlements:application-identifier)" = "$TEAM.$id" ] || fail "The profile \"$name\" is not for $id (or not for the team in Signing.xcconfig)."
  [ "$(pb "$p" Entitlements:get-task-allow)" = "false" ] || fail "The profile \"$name\" is a development profile: make an App Store Connect one."
  pb "$p" ProvisionedDevices > /dev/null && fail "The profile \"$name\" is an ad hoc profile: make an App Store Connect one."
  pb "$p" Entitlements:com.apple.security.application-groups | grep -q "$GROUP" || fail "The profile \"$name\" lacks the App Group $GROUP: turn it on for the App ID, then make the profile again."
  if [ "$want" = "carplay" ]; then
    [ "$(pb "$p" Entitlements:com.apple.developer.carplay-audio)" = "true" ] || fail "The profile \"$name\" lacks CarPlay Audio: turn it on for the App ID, then make the profile again."
  fi
  echo "   profile \"$name\": fits, valid until ${bestexp%%T*}"
  rm -f "$p"
}

if [ -z "$REHEARSE" ]; then
  echo "== signing check"
  [ "$(security find-identity -v -p codesigning 2>/dev/null | grep -c '"Apple Distribution: ')" -ge 1 ] \
    || fail "No Apple Distribution certificate found in the keychain."
  check_profile "$APP_PROFILE" "$APP_ID" carplay
  check_profile "$WIDGET_PROFILE" "$WIDGET_ID" ""
fi

# Compile once per commit: a rehearsal leaves the compiled clone, and the signed run uses it again.
if [ "$(cat "$SRC/.compiled" 2>/dev/null)" != "$COMMIT $VER+$BUILD" ]; then
  echo "== clone"
  rm -rf "$SRC"
  git clone -q "$REPO" "$SRC" || fail "Could not clone $REPO."
  git -C "$SRC" checkout -q --detach "$COMMIT" || fail "Commit ${COMMIT[1,7]} is not in $REPO: push it first."
  grep -q "^version: $VER+$BUILD\$" "$SRC/pubspec.yaml" || fail "pubspec.yaml at commit ${COMMIT[1,7]} is not $VER+$BUILD: commit the version first."
  cp "$SIGNING" "$SRC/ios/Flutter/Signing.xcconfig"
  echo "== compile (several minutes)"
  # The generated code (translations, database) is not in git: make it first, as tool/bootstrap.sh does.
  ( cd "$SRC" && flutter pub get && flutter gen-l10n && dart run build_runner build \
      && flutter build ios --release --no-codesign --obfuscate --split-debug-info="$SYMBOLS" ) > "$WORK/compile.log" 2>&1 \
    || { echo "COMPILE FAILED:"; tail -25 "$WORK/compile.log"; exit 1; }
  echo "$COMMIT $VER+$BUILD" > "$SRC/.compiled"
else
  echo "== using the clone compiled before ($SRC)"
fi
cd "$SRC"
[ "$(git rev-parse HEAD)" = "$COMMIT" ] || fail "$SRC is not at commit ${COMMIT[1,7]}: delete it and run again."
GX=ios/Flutter/Generated.xcconfig
grep -q "^FLUTTER_BUILD_NAME=$VER\$" $GX || fail "The compiled app is not $VER: delete $SRC and run again."
grep -q "^FLUTTER_BUILD_NUMBER=$BUILD\$" $GX || fail "The compiled app is not build $BUILD: delete $SRC and run again."
grep -q "^DART_OBFUSCATION=true" $GX || fail "The compiled app is not obfuscated: delete $SRC and run again."

echo "== manual signing, in the clone only"
# The app and its widget get manual signing in their Release settings, found by bundle id.
# The repository's project keeps automatic signing, and no signing setting goes on the xcodebuild command line.
TEAM="$TEAM" APP_ID="$APP_ID" WIDGET_ID="$WIDGET_ID" APP_PROFILE="$APP_PROFILE" WIDGET_PROFILE="$WIDGET_PROFILE" \
  "$RUBY" -e '
require "xcodeproj"
project = Xcodeproj::Project.open(File.join(ARGV[0], "ios", "Runner.xcodeproj"))
profiles = { ENV["APP_ID"] => ENV["APP_PROFILE"], ENV["WIDGET_ID"] => ENV["WIDGET_PROFILE"] }
done = []
project.targets.each do |target|
  target.build_configurations.each do |config|
    next unless config.name == "Release"
    s = config.build_settings
    profile = profiles[s["PRODUCT_BUNDLE_IDENTIFIER"]]
    next unless profile
    s["CODE_SIGN_STYLE"] = "Manual"
    s["DEVELOPMENT_TEAM"] = ENV["TEAM"]
    s["CODE_SIGN_IDENTITY"] = "Apple Distribution"
    s["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = "Apple Distribution"
    s["PROVISIONING_PROFILE_SPECIFIER"] = profile
    s.delete("PROVISIONING_PROFILE")
    done << "   #{target.name} -> #{profile}"
  end
end
project.save
puts done
abort "STOP: expected the app and the widget, found #{done.size} target(s)." unless done.size == 2
' "$SRC" || exit 1

echo "== archive (several minutes)"
EXTRA=()
[ -n "$REHEARSE" ] && EXTRA=(CODE_SIGNING_ALLOWED=NO)
# DerivedData inside /tmp: Xcode's default folder puts /Users/<this Mac's user>/ into the binaries.
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath "$WORK/DerivedData" \
  -archivePath "$WORK/Runner.xcarchive" archive "${EXTRA[@]}" > "$WORK/archive.log" 2>&1 \
  || { echo "ARCHIVE FAILED:"; grep -E "error:|errSec|Code Sign|Provisioning|requires a" "$WORK/archive.log" | sort -u | head -15; echo "(full log: $WORK/archive.log)"; exit 1; }

inspect() {  # $1 = the .app folder
  local app=$1 w="$1/PlugIns/NowPlayingWidget.appex"
  [ -d "$w" ] || fail "The widget is not inside the app."
  echo "inside: app $(pb "$app/Info.plist" CFBundleShortVersionString) ($(pb "$app/Info.plist" CFBundleVersion)), widget $(pb "$w/Info.plist" CFBundleShortVersionString) ($(pb "$w/Info.plist" CFBundleVersion)), files naming /Users/$(id -un)/: $(grep -rlaE "/Users/$(id -un)/" "$app" | wc -l | tr -d ' ')"
  [ "$(pb "$app/Info.plist" CFBundleShortVersionString) $(pb "$app/Info.plist" CFBundleVersion)" = "$VER $BUILD" ] || fail "The app inside is not $VER ($BUILD)."
  [ "$(pb "$w/Info.plist" CFBundleShortVersionString) $(pb "$w/Info.plist" CFBundleVersion)" = "$VER $BUILD" ] || fail "The widget inside is not $VER ($BUILD)."
}

if [ -n "$REHEARSE" ]; then
  inspect "$WORK/Runner.xcarchive/Products/Applications/Runner.app"
  echo "REHEARSAL OK: compiled and archived without signing. Nothing was exported."
  echo "The compiled clone stays in $SRC for the signed run of this commit."
  exit 0
fi

echo "== export"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$APP_ID</key><string>$APP_PROFILE</string>
    <key>$WIDGET_ID</key><string>$WIDGET_PROFILE</string>
  </dict>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$WORK/Runner.xcarchive" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" > "$WORK/export.log" 2>&1 \
  || { echo "EXPORT FAILED:"; grep -E "error:|errSec|Code Sign|Provisioning" "$WORK/export.log" | sort -u | head -15; echo "(full log: $WORK/export.log)"; exit 1; }
rm -f "$WORK/ExportOptions.plist"
IPA=$(ls "$WORK"/export/*.ipa | head -1)
cp "$IPA" "$IPA_OUT"

# A look inside the exported app: versions, what it was signed with, and no file naming this Mac's user folder.
mkdir -p "$WORK/check" && (cd "$WORK/check" && unzip -q "$IPA_OUT")
P=$(ls -d "$WORK"/check/Payload/*.app | head -1)
inspect "$P"
ENT=$(codesign -d --entitlements - --xml "$P" 2>/dev/null || true)
has() { print -r -- "$ENT" | grep -q "$1" && echo yes || echo NO; }
echo "signed with: CarPlay Audio $(has com.apple.developer.carplay-audio), App Group $(has "$GROUP"), App Store profile $(print -r -- "$ENT" | grep -A1 get-task-allow | grep -q false && echo yes || echo NO)"

# Symbols of an earlier build with the same version and build number are moved aside, never overwritten.
if [ -e "$KEEP" ]; then mv "$KEEP" "$KEEP.replaced-$(date +%Y%m%d-%H%M%S)"; fi
mkdir -p "$KEEP"
cp -R "$SRC/$SYMBOLS" "$KEEP/dart-symbols" 2>/dev/null || echo "   (no Dart symbols found at $SYMBOLS)"
cp -R "$WORK/Runner.xcarchive/dSYMs" "$KEEP/dSYMs" 2>/dev/null || true
echo "symbols kept in $KEEP"

echo "DONE: $IPA_OUT ($(stat -f %z "$IPA_OUT") bytes)"
shasum -a 256 "$IPA_OUT" | cut -d' ' -f1

# The clone, the archive and the pub cache have done their job: the IPA and the symbols are what stay.
rm -rf "$SRC" "$WORK" "$PUB_CACHE" 2>/dev/null || true
