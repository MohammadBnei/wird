#!/usr/bin/env bash
# The gate. Its exit code is the verdict; qa-report.json is the artifact.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)
REPORT="$ROOT/qa-report.json"
ENTRIES=$(mktemp)
RUNLOG=$(mktemp)
trap 'rm -f "$ENTRIES" "$RUNLOG"' EXIT
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

# The release manifest is the one artefact a reader installs and the one nothing
# here used to read. That is not hypothetical: a release APK shipped with no
# INTERNET permission, because Flutter grants it to the debug and profile
# manifests only, and every recitation failed silently — AudioCache.prefetch
# swallows a fetch error by design, so the app looked well and played nothing.
release_manifest_is_shippable() {
	local manifest="$ROOT/app/android/app/src/main/AndroidManifest.xml" bad=0
	if ! grep -q 'android.permission.INTERNET' "$manifest"; then
		printf 'the release manifest asks for no INTERNET permission, so every recitation fails silently on a real phone\n'
		bad=1
	fi
	if ! grep -q 'android:label="Wird"' "$manifest"; then
		printf 'the launcher label is not the name of the app, so the icon on the phone is captioned something else\n'
		bad=1
	fi
	if [ ! -f "$ROOT/app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" ]; then
		printf 'there is no adaptive icon, which is what Flutter ships by default and what the Flutter logo comes back as\n'
		bad=1
	fi
	return $bad
}

# A unit test builds the thing it tests, so a green suite says the unit works
# and says nothing about whether the app ever calls it. `syncNow` had
# twenty-four call sites, all of them in app/test and none in app/lib: the
# outbox, the retry budget, the park and dead-letter rules and the change
# cursor were all built, certified and never once run in a shipped build. No
# understood aya, no prayer and no kept note had ever left a phone.
#
# Each name below is a door out of the app. The reason it is listed is that
# nothing inside the app breaks when it is never called, which is exactly the
# defect a test suite cannot see.
the_app_calls_what_it_ships() {
	local bad=0 home callers
	while IFS='|' read -r fn why; do
		[ -z "$fn" ] && continue
		# Called from somewhere other than the file that declares it. A door
		# used only by its own room is not a door.
		home=$(grep -rl "^[A-Za-z].*[[:space:]]$fn(" "$ROOT/app/lib" --include='*.dart' | head -1)
		callers=$(grep -rl "$fn(" "$ROOT/app/lib" --include='*.dart' | grep -vcx "$home")
		[ "${callers:-0}" -gt 0 ] && continue
		printf 'nothing in app/lib calls %s, so %s\n' "$fn" "$why"
		bad=1
	done <<-'NAMES'
		syncNow|no write a reader makes ever leaves their phone
	NAMES
	return $bad
}

gates_all_accounted() {
	local missing
	missing=$(jq -s -r '[range(1;8)] - ([.[].gate] | unique) | join(", ")' "$ENTRIES")
	[ -z "$missing" ] && return 0
	printf 'nothing in the report answers gate %s, so six checks read as all seven\n' "$missing"
	return 1
}

# Which of the three targets device.sh resolved. Each journey declares what it
# needs and skips loudly when the target cannot do it, so the answer has to
# reach the app as more than a device id.
target_kind() {
	[ "$1" = macos ] && { echo macos; return; }
	if xcrun simctl list devices available --json 2>/dev/null |
		jq -e --arg u "$1" 'any(.devices[][]; .udid == $u)' >/dev/null; then
		echo simulator
	else
		echo iphone
	fi
}

# The ledger is what the gate remembers between phases: every journey it has
# ever seen, against the phases it was skipped in. A journey that ran clears
# its list. Two phases without a run means it has never run, and a journey that
# stops being reported altogether has been dropped — both of which read as a
# pass otherwise.
JOURNEY_LEDGER="$ROOT/qa-skips.json"

every_journey_still_runs() {
	local phase=${WIRD_PHASE:-4} next stuck dropped
	[ -f "$JOURNEY_LEDGER" ] || echo '{}' >"$JOURNEY_LEDGER"
	dropped=$(jq -r --argjson run "$1" '
		[keys[] | select(. as $k | $run | map(.journey) | index($k) | not)] | join("; ")' "$JOURNEY_LEDGER")
	next=$(jq --argjson phase "$phase" --argjson run "$1" '
		reduce $run[] as $j (.;
			.[$j.journey] = (if $j.status == "skip"
				then ((.[$j.journey] // []) + [$phase] | unique)
				else [] end))' "$JOURNEY_LEDGER")
	printf '%s\n' "$next" >"$JOURNEY_LEDGER"

	if [ -n "$dropped" ]; then
		printf 'a journey the gate has run before is no longer in the suite, so the loop it covered is now uncovered: %s\n' "$dropped"
		return 1
	fi
	stuck=$(jq -r 'to_entries
		| map(select(.value | length >= 2) | "\(.key) — skipped in phases \(.value | join(", "))")
		| join("; ")' <<<"$next")
	[ -z "$stuck" ] && return 0
	printf 'a journey has been skipped on every target for two phases running, so it has never run: %s\n' "$stuck"
	return 1
}

# Runs every journey shipped so far, not only the newest, and records each one
# by name: a run that quietly stopped reporting a journey reads as a pass
# otherwise.
run_journeys() {
	local dev kind out one status run count
	if ! dev=$("$ROOT/scripts/device.sh") || [ -z "$dev" ]; then
		record "integration journeys" fail "scripts/device.sh resolved no e2e target, so no journey ran"
		printf 'FAIL  integration journeys — no target\n'
		failed=1
		return
	fi
	kind=$(target_kind "$dev")
	printf 'e2e target: %s (%s)\n' "$dev" "$kind"

	# One file per run. Handed the whole directory, the runner builds a file at
	# a time in parallel and Xcode refuses the second build against the same
	# location ("build database is locked"), so one journey file dies before it
	# starts — which the ledger below reads as a journey that no longer exists.
	# --concurrency is parsed and ignored for integration tests, so the serial
	# run has to be the loop.
	out=""
	status=0
	# Job control, so each run is a process group of its own and the app it
	# launched can be killed by that group id.
	set -m
	for file in "$ROOT"/app/integration_test/*_test.dart; do
		in_app fvm flutter test "integration_test/$(basename "$file")" -d "$dev" --dart-define=WIRD_TARGET="$kind" >"$RUNLOG" 2>&1 &
		runner=$!
		wait "$runner" || status=1
		# The desktop app outlives its own run, and macOS answers the next
		# launch by foregrounding the instance already open, so the following
		# journey file waits for a debug connection that never arrives.
		#
		# Killing the group rather than every process whose path matches: the
		# pattern kill took down the app of every agent running this gate at
		# the same time, including ones halfway through a journey.
		kill -- -"$runner" 2>/dev/null
		out="$out$(cat "$RUNLOG")"$'\n'
		sleep 1
	done
	set +m
	run=$(grep -o 'WIRD-JOURNEY {.*}' <<<"$out" | sed 's/^WIRD-JOURNEY //' | jq -s 'unique_by(.journey)')

	if [ "$status" -ne 0 ]; then
		record "integration journeys on $kind" fail "$out"
		printf 'FAIL  integration journeys on %s\n%s\n' "$kind" "$out"
		failed=1
	elif [ "$(jq length <<<"$run")" -eq 0 ]; then
		record "integration journeys on $kind" fail "the run exited clean and reported no journey at all, which reads as a pass while nothing was exercised:\n$out"
		printf 'FAIL  integration journeys on %s — nothing reported\n' "$kind"
		failed=1
	fi

	count=$(jq length <<<"$run")
	for i in $(seq 0 $((count - 1))); do
		local name reason state
		name=$(jq -r ".[$i].journey" <<<"$run")
		state=$(jq -r ".[$i].status" <<<"$run")
		reason=$(jq -r ".[$i].reason" <<<"$run")
		if [ "$state" = skip ]; then
			skip "journey: $name" "$reason"
		else
			record "journey: $name" pass "ran on $kind"
			printf 'PASS  journey: %s\n' "$name"
		fi
	done

	check "every journey still runs, and none has been skipped for two phases" every_journey_still_runs "$run"
}

# 1 — Go builds, vets and tests. ./... is not a valid pattern at a workspace root
# that is not itself a module (go1.27.1), so each module is named.
GATE=1
# The store and handler tests run against a real Postgres 18, each in a
# database of its own: a mocked one cannot tell you a unique constraint is
# missing, which is the whole defence against a prayer counted twice.
if command -v docker >/dev/null 2>&1; then
	docker compose up -d --wait postgres >/dev/null 2>&1 ||
		printf 'postgres did not come up; the server tests will say so\n'
fi
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
	run_journeys
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

if [ -d "$ROOT/app/lib" ]; then
	check "the app calls what it ships" the_app_calls_what_it_ships
else
	skip "the app calls what it ships" "app/lib does not exist before the client is built"
fi

if [ -f "$ROOT/app/android/app/src/main/AndroidManifest.xml" ]; then
	check "the release manifest is shippable" release_manifest_is_shippable
else
	skip "the release manifest is shippable" "app/android does not exist before the Android target is added"
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
