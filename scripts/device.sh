#!/usr/bin/env bash
# Prints one Flutter device id for `flutter run -d` / `flutter test integration_test/ -d`.
# Order: attached iPhone > the iPhone 16 simulator on iOS 18.6 > the macOS desktop target.
# Resolved by name every time: a pinned UDID rots on the next machine.
set -uo pipefail

RUNTIME=${WIRD_IOS_RUNTIME:-iOS-18-6}
SIM_NAME=${WIRD_SIM_NAME:-iPhone 16}

iphone=$(xcrun xcdevice list 2>/dev/null |
	jq -r 'map(select(.simulator == false and .platform == "com.apple.platform.iphoneos" and .available == true))
	       | .[0].identifier // empty')
if [ -n "$iphone" ]; then
	echo "$iphone"
	exit 0
fi

sim=$(xcrun simctl list devices available --json 2>/dev/null |
	jq -r --arg runtime "$RUNTIME" --arg name "$SIM_NAME" \
		'.devices | to_entries
		 | map(select(.key | endswith($runtime)))
		 | map(.value[] | select(.name == $name))
		 | flatten | .[0].udid // empty')
if [ -n "$sim" ]; then
	# Boots it if it is shut down, then waits until it can accept an install.
	xcrun simctl bootstatus "$sim" -b >&2 || exit 1
	echo "$sim"
	exit 0
fi

echo macos
