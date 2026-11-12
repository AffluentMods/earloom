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
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b

flutter drive -d "$udid" --driver=test_driver/integration_test.dart --target=integration_test/app_launch_test.dart

echo "== Deep link through iOS"
flutter build ios --simulator --debug
xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app
xcrun simctl terminate "$udid" com.affluentlabs.earloom || true
# openurl fails when no installed app claims the scheme.
xcrun simctl openurl "$udid" "earloom://item/test"
sleep 15
xcrun simctl io "$udid" screenshot "$out/ios_08_os_deep_link_item.png"
xcrun simctl spawn "$udid" launchctl list | grep -q "com.affluentlabs.earloom" \
  || { echo "FAIL: the app is not running after the deep link"; exit 1; }
echo "OK: iOS device checks passed"
