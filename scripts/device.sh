#!/usr/bin/env bash
# Prints one Flutter device id for `flutter run -d` / `flutter test integration_test/ -d`.
# Order: attached iPhone > the iPhone 16 simulator on iOS 18.6 > the macOS desktop target.
# Resolved by name every time: a pinned UDID rots on the next machine.
set -uo pipefail

RUNTIME=${WIRD_IOS_RUNTIME:-iOS-18-6}
SIM_NAME=${WIRD_SIM_NAME:-iPhone 16}
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/app/ios/Runner.xcodeproj"

# Xcode resolves a build destination separately from simctl's device list, and
# with the iOS platform not installed every iOS destination is ineligible — so
# a simulator simctl boots happily is one no build can reach. Ask Xcode before
# naming a target, or the caller gets an id that only fails later.
buildable() {
	xcodebuild -project "$PROJECT" -scheme Runner -showdestinations 2>/dev/null |
		sed -n '/Ineligible destinations/q;p' | grep -q "id:$1"
}

# Cabled only. A wirelessly paired iPhone is listed, is available, and builds —
# and then every journey dies at load with "Cannot start app on wirelessly
# tethered iOS device", which reads as six dropped journeys rather than as
# somebody's phone being on the same wifi.
iphone=$(xcrun xcdevice list 2>/dev/null |
	jq -r 'map(select(.simulator == false and .platform == "com.apple.platform.iphoneos"
	              and .available == true and .interface == "usb"))
	       | .[0].identifier // empty')
if [ -n "$iphone" ] && buildable "$iphone"; then
	echo "$iphone"
	exit 0
fi

sim=$(xcrun simctl list devices available --json 2>/dev/null |
	jq -r --arg runtime "$RUNTIME" --arg name "$SIM_NAME" \
		'.devices | to_entries
		 | map(select(.key | endswith($runtime)))
		 | map(.value[] | select(.name == $name))
		 | flatten | .[0].udid // empty')
if [ -n "$sim" ] && buildable "$sim"; then
	# Boots it if it is shut down, then waits until it can accept an install.
	xcrun simctl bootstatus "$sim" -b >&2 || exit 1
	echo "$sim"
	exit 0
fi

if [ -n "$iphone$sim" ]; then
	echo "an iOS target is present but Xcode has no eligible destination for it," >&2
	echo "so nothing can be built for it; falling back to the macOS target." >&2
fi
echo macos
