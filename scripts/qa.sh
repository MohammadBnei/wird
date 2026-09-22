#!/usr/bin/env bash
# The gate. Its exit code is the verdict; qa-report.json is the artifact.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)
REPORT="$ROOT/qa-report.json"
ENTRIES=$(mktemp)
trap 'rm -f "$ENTRIES"' EXIT
failed=0

record() {
	jq -n --arg name "$1" --arg status "$2" --arg detail "$3" \
		'{check: $name, status: $status, detail: $detail}' >>"$ENTRIES"
}

check() {
	local name=$1 out
	shift
	if out=$("$@" 2>&1); then
		record "$name" pass ""
		printf 'PASS  %s\n' "$name"
	else
		record "$name" fail "$out"
		printf 'FAIL  %s\n%s\n' "$name" "$out"
		failed=1
	fi
}

skip() {
	record "$1" skip "$2"
	printf 'SKIP  %s — %s\n' "$1" "$2"
}

in_app() { (cd "$ROOT/app" && "$@"); }

# Assembled from two pieces so this script is not its own first hit.
golden_refresh_flag='--update'"-goldens"

no_golden_refresh() {
	local hits
	hits=$(
		git grep -I -n -F -e "$golden_refresh_flag" -- . 2>/dev/null
		git diff --cached -U0 2>/dev/null | grep -F -e "$golden_refresh_flag"
	)
	[ -z "$hits" ] && return 0
	printf 'the golden-refresh flag appears in tracked files or the staged diff:\n%s\n' "$hits"
	return 1
}

# Go: ./... is not a valid pattern at a workspace root that is not itself a
# module (go1.27.1), so each module is named.
GO_PKGS=(./jidhr/... ./server/...)
check "go build" go build "${GO_PKGS[@]}"
check "go vet" go vet "${GO_PKGS[@]}"
check "go test" go test -p 1 "${GO_PKGS[@]}"

if [ -d "$ROOT/app" ]; then
	check "flutter analyze" in_app fvm flutter analyze
	check "flutter test" in_app fvm flutter test
else
	skip "flutter analyze" "app/ does not exist yet"
	skip "flutter test" "app/ does not exist yet"
fi

check "no golden refresh flag" no_golden_refresh

jq -s --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
	generated_at: $generated_at,
	verdict: (if any(.[]; .status == "fail") then "fail" else "pass" end),
	counts: {
		pass: map(select(.status == "pass")) | length,
		fail: map(select(.status == "fail")) | length,
		skip: map(select(.status == "skip")) | length
	},
	checks: .
}' "$ENTRIES" >"$REPORT"

printf '\n%s\n' "$(jq -r '"\(.counts.pass) passed, \(.counts.fail) failed, \(.counts.skip) skipped — \(.verdict)"' "$REPORT")"
printf 'report: %s\n' "$REPORT"

exit "$failed"
