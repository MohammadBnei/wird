#!/usr/bin/env bash
# The gate. Its exit code is the verdict; qa-report.json is the artifact.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)
REPORT="$ROOT/qa-report.json"
ENTRIES=$(mktemp)
trap 'rm -f "$ENTRIES"' EXIT
failed=0

# Which row of the plan's check table an entry answers. Every entry carries one, so
# a report that silently covers six of the seven checks is a failure, not a pass.
GATE=0

record() {
	jq -n --argjson gate "$GATE" --arg name "$1" --arg status "$2" --arg detail "$3" \
		'{gate: $gate, check: $name, status: $status, detail: $detail}' >>"$ENTRIES"
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

# Assembled the same way, for the same reason.
todo_marker='TO'"DO"

todos_carry_an_issue() {
	local hits
	# CONTRIBUTING.md states the rule; stating it is not an instance of breaking it.
	hits=$(git grep -I -n --untracked -F -e "$todo_marker" -- . ':!CONTRIBUTING.md' 2>/dev/null | grep -vF "$todo_marker(#")
	[ -z "$hits" ] && return 0
	printf 'a marker with no issue number behind it never comes back:\n%s\n' "$hits"
	return 1
}

# ponytail: one direction only — the ledger claims a tool that is not installed.
# The reverse, a formula nobody wrote down, is unreadable on a shared machine
# carrying seventy unrelated leaves. Snapshot a baseline if Wird gets a build box.
toolchain_recorded() {
	local installed missing=""
	installed=$( { brew list --formula -1; brew list --cask -1; } 2>/dev/null)
	while read -r tool; do
		grep -qxF "$tool" <<<"$installed" || missing="$missing $tool"
	done < <(sed -n '/brew-leaves:start/,/brew-leaves:end/p' docs/toolchain.md | sed -n 's/^- //p')
	[ -z "$missing" ] && return 0
	printf 'docs/toolchain.md records tools that are not installed:%s\n' "$missing"
	return 1
}

corpus_under_budget() {
	local bytes limit=$((60 * 1024 * 1024))
	bytes=$(wc -c <"$ROOT/app/assets/corpus.db")
	[ "$bytes" -le "$limit" ] && return 0
	printf 'corpus.db is %s bytes, over the %s byte release budget that decides whether the bundled corpus works at all\n' "$bytes" "$limit"
	return 1
}

gates_all_accounted() {
	local missing
	missing=$(jq -s -r '[range(1;8)] - ([.[].gate] | unique) | join(", ")' "$ENTRIES")
	[ -z "$missing" ] && return 0
	printf 'nothing in the report answers gate %s, so six checks read as all seven\n' "$missing"
	return 1
}

# 1 — Go builds, vets and tests. ./... is not a valid pattern at a workspace root
# that is not itself a module (go1.27.1), so each module is named.
GATE=1
GO_PKGS=(./jidhr/... ./server/...)
check "go build" go build "${GO_PKGS[@]}"
check "go vet" go vet "${GO_PKGS[@]}"
check "go test" go test -p 1 "${GO_PKGS[@]}"

# 2 — the Flutter suite, and goldens that were not refreshed into passing.
GATE=2
if [ -d "$ROOT/app" ]; then
	check "flutter analyze" in_app fvm flutter analyze
	check "flutter test" in_app fvm flutter test
else
	skip "flutter analyze" "app/ does not exist yet"
	skip "flutter test" "app/ does not exist yet"
fi
check "no golden refresh flag" no_golden_refresh

# 3 — every e2e journey shipped so far, from phase 4 on.
GATE=3
if [ -d "$ROOT/app/integration_test" ]; then
	check "integration journeys" in_app fvm flutter test integration_test/ -d "$("$ROOT/scripts/device.sh")"
else
	skip "integration journeys" "app/integration_test/ does not exist before phase 4"
fi

# 4, 5, 6 — judgments, not commands. They are recorded so the report never reads as
# complete while a human check has not happened.
GATE=4
if [ -d "$ROOT/app" ]; then
	skip "per-screen acceptance rows" "the QA agent maps each touched row to a named test; this script cannot read the table"
else
	skip "per-screen acceptance rows" "no screen exists yet: app/ does not exist"
fi

GATE=5
skip "test-meaning audit" "the fresh-context QA agent reads the tests added this phase; a script cannot tell whether a name states the failure it prevents"

GATE=6
check "every marker carries an issue number" todos_carry_an_issue
skip "comment audit" "the fresh-context QA agent reads the diff for restating comments and dead code"

# 7 — the toolchain record is falsifiable, and the shipped corpus fits the budget
# that decides whether the bundled-corpus split works at all.
GATE=7
if command -v brew >/dev/null 2>&1; then
	check "toolchain ledger matches what is installed" toolchain_recorded
else
	skip "toolchain ledger matches what is installed" "Homebrew is not installed on this machine"
fi

if [ -f "$ROOT/app/assets/corpus.db" ]; then
	check "corpus.db under budget" corpus_under_budget
else
	skip "corpus.db under budget" "app/assets/corpus.db is built by the ETL phase; the 60 MB budget is checked from then on"
fi

GATE=0
check "every gate check is accounted for" gates_all_accounted

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
