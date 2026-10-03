#!/usr/bin/env bash
# Captures the store screenshots from a simulator, at the size the App Store
# asks for. app/integration_test/store_screens.dart walks the screens and
# prints `WIRD-SHOT <name>`; this captures the simulator each time it does.
#
#   scripts/store-screens.sh "iPhone 17 Pro Max" out/iphone   # 6.9", 1320x2868
#   scripts/store-screens.sh "iPad Pro 13-inch (M5)" out/ipad # 13", 2064x2752
set -euo pipefail

NAME=${1:?simulator device type name}
OUT=${2:?output directory}
RUNTIME=${WIRD_IOS_RUNTIME:-iOS-26-5}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# A simulator of its own, so the screenshots never inherit a reader's data.
SIM="wird-store $NAME"
udid=$(xcrun simctl list devices --json | jq -r --arg n "$SIM" '[.devices[][] | select(.name == $n)][0].udid // empty')
if [ -z "$udid" ]; then
	type=$(xcrun simctl list devicetypes --json | jq -r --arg n "$NAME" '.devicetypes[] | select(.name == $n) | .identifier')
	udid=$(xcrun simctl create "$SIM" "$type" "com.apple.CoreSimulator.SimRuntime.$RUNTIME")
fi
# Booting an already booted simulator is the only error worth ignoring.
xcrun simctl boot "$udid" 2>&1 | grep -v "current state: Booted" || true
xcrun simctl bootstatus "$udid" -b >/dev/null
# The listing shows the app, not somebody's afternoon.
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active \
	--wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

cd "$ROOT/app"
fvm flutter test integration_test/store_screens.dart -d "$udid" 2>&1 | while IFS= read -r line; do
	echo "$line"
	if [[ "$line" =~ WIRD-SHOT\ ([A-Za-z0-9_-]+) ]]; then
		sleep 1
		xcrun simctl io "$udid" screenshot "$OUT/${BASH_REMATCH[1]}.png" >/dev/null
	fi
done
xcrun simctl status_bar "$udid" clear
ls "$OUT"
