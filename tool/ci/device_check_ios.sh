#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# macOS only. Boots an iPhone simulator, then runs:
#   1. the device test (launch, tabs, theme, previews, in-app deep links)
#   2. a deep link through iOS itself (simctl openurl)
# Screenshots end up in build/device-screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/device-screenshots
mkdir -p "$out"

# The newest available iPhone simulator.
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit("iOS-", 1)[-1].split("-") if p.isdigit())
    for d in items:
        if d["name"].startswith("iPhone") and (best is None or version > best[0]):
            best = (version, d["udid"], d["name"])
print(best[1])
')
echo "Simulator: $udid"

# Runs a command with a time limit (macOS has no timeout(1); perl does).
# A hang then fails with a clear message instead of using up the whole job.
limit() {
  local seconds=$1
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@" || {
    local code=$?
    [[ $code -eq 142 ]] && echo "FAIL: timed out after ${seconds}s: $*"
    return $code
  }
}

# A simulator can come up half-started ("Waiting on System App", then a
# failed boot status). Only trust it once it answers a command, and give it
# one clean retry: shut down, erase, boot again.
ready() {
  limit 300 xcrun simctl bootstatus "$udid" -b >/dev/null \
    && limit 60 xcrun simctl spawn "$udid" launchctl print system >/dev/null
}
boot() {
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  limit 120 xcrun simctl boot "$udid"
}
if ! { boot && ready; }; then
  echo "Simulator did not come up cleanly. Erasing it and trying once more."
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  limit 120 xcrun simctl erase "$udid"
  boot && ready || { echo "FAIL: the simulator did not boot"; exit 1; }
fi
echo "Simulator ready"

limit 1500 flutter drive -d "$udid" --driver=test_driver/integration_test.dart --target=integration_test/app_launch_test.dart

echo "== Deep link through iOS"
limit 900 flutter build ios --simulator --debug
app=build/ios/iphonesimulator/Runner.app
bundle=com.affluentlabs.earloom

# 1. The built app declares the earloom:// scheme to iOS.
scheme=$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$app/Info.plist")
[[ "$scheme" == "earloom" ]] || { echo "FAIL: Info.plist declares scheme '$scheme', expected earloom"; exit 1; }
echo "Info.plist declares the earloom:// scheme"

limit 120 xcrun simctl install "$udid" "$app"
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true

# Simulator apps are ordinary processes on the Mac, so look for them there.
running() { pgrep -f "/Runner.app/Runner" >/dev/null; }
diagnose() {
  echo "-- Simulator log for the app, last 2 minutes:"
  xcrun simctl spawn "$udid" log show --last 2m --style compact --predicate 'process == "Runner"' | tail -80 || true
  echo "-- Recent crash reports:"
  ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i runner | head -3 || true
}

# 2. The standalone build starts and stays up.
limit 60 xcrun simctl launch "$udid" "$bundle"
sleep 15
running || { echo "FAIL: the app did not stay running after launch"; diagnose; exit 1; }
echo "App launched and running"

# 3. iOS hands the link to the running app. A cold start through a custom
#    scheme can stop at a system "Open in Earloom?" prompt on the simulator,
#    so the link is sent while the app runs. openurl fails when no installed
#    app claims the scheme.
limit 60 xcrun simctl openurl "$udid" "earloom://item/test"
sleep 5
limit 60 xcrun simctl io "$udid" screenshot "$out/ios_08_os_deep_link_item.png"
running || { echo "FAIL: the app is not running after the deep link"; diagnose; exit 1; }
echo "Deep link delivered, app still running"
echo "OK: iOS device checks passed"
