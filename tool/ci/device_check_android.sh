#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Runs on a booted Android emulator (CI) or a connected device:
#   1. the device test (launch, tabs, theme, previews, in-app deep links)
#   2. deep links through Android itself (am start), which the Flutter test
#      cannot reach
# Screenshots end up in build/device-screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/device-screenshots
mkdir -p "$out"
pkg=com.affluentlabs.earloom

# Keep the device log (minus the very chatty semantics dumps) so a failure
# can be diagnosed from the artifact.
adb logcat -c || true
adb logcat -v time AccessibilityBridge:S '*:I' >"$out/android-logcat.txt" 2>&1 &
logcat_pid=$!
trap 'kill $logcat_pid 2>/dev/null || true' EXIT

# FLUTTER_DRIVE_ARGS lets CI adjust the run for its emulator (see devices.yml).
# shellcheck disable=SC2086
flutter drive ${FLUTTER_DRIVE_ARGS:-} --driver=test_driver/integration_test.dart --target=integration_test/app_launch_test.dart

echo "== Deep links through Android"
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# A plain launch first, for a screenshot of Home.
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 20
adb exec-out screencap -p >"$out/android_01_home.png"
adb shell am force-stop "$pkg"

# A link the app owns must open the app.
result=$(adb shell am start -W -a android.intent.action.VIEW -d "earloom://item/test" 2>&1)
echo "$result"
grep -q "$pkg" <<<"$result" || { echo "FAIL: earloom://item/test did not open $pkg"; exit 1; }
# Debug builds start slowly on an emulator: let the first frame land.
sleep 20
adb exec-out screencap -p >"$out/android_08_os_deep_link_item.png"
front=$(adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -2 || true)
echo "$front"
grep -q "$pkg" <<<"$front" || { echo "FAIL: $pkg is not in front after the deep link"; exit 1; }

# A link outside the two the manifest declares must not reach the app.
other=$(adb shell am start -W -a android.intent.action.VIEW -d "earloom://settings/delete-everything" 2>&1 || true)
echo "$other"
if grep -q "Activity: $pkg" <<<"$other"; then
  echo "FAIL: an undeclared earloom:// link was routed to the app"; exit 1
fi
echo "OK: Android device checks passed"
