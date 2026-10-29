#!/usr/bin/env bash
# The app's build name and number, as GITHUB_OUTPUT lines: one place for
# apk.yml (apk and aab jobs) and ipa.yml, so the APK, Play and TestFlight never
# disagree on a release. Needs the full history (fetch-depth: 0).
#
# The build name is the release tag (ADR 0041), not the pubspec line. From
# main, which never publishes, it is the last release plus the commit, the way
# release.yml names an untagged image, so a report sent from that build claims
# no release it is not. The build number is the commit count: it only rises,
# and was 548 at v0.0.14 against the pubspec's 15.
# ponytail: past 999 commits the arm64 code (2000+N) runs into the next ABI's
# 3000 range; harmless while only arm64 ships, and it still rises.
set -euo pipefail

if [ "${GITHUB_REF_TYPE:-}" = tag ]; then
	name=${GITHUB_REF_NAME#v}
else
	# Separate assignments: in "$(a)+$(b)" only b's exit status counts, and a
	# ref with no v* tag would ship as "+<sha>".
	last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)
	sha=$(git rev-parse --short=12 HEAD)
	name="${last#v}+$sha"
fi
number=$(git rev-list --count HEAD)

echo "name=$name"
echo "number=$number"
