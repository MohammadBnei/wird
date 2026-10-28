#!/usr/bin/env bash
# Refuses non-Conventional subjects and AI attribution in BASE..HEAD.
# Usage: scripts/check-commits.sh BASE HEAD | --self-test
# Merge commits skip the subject rule (their subjects are git's or GitHub's
# own) but not the attribution rule. git's own `Revert "..."` subject passes;
# fixup!/squash! do not, they are meant to be squashed before review.
set -uo pipefail

# ponytail: plain "generated with" also refuses a human body saying
# "Generated with sqlc"; reword it, or narrow the pattern if it bites.
type='^((feat|fix|refactor|test|docs|chore|perf|build|ci|style|revert)(\([^)]+\))?!?: .+|Revert ".+)'
bad='noreply@anthropic\.com|claude\.ai/|generated with|co-authored-by:.*(claude|anthropic)'

check() {
  local fail=0 c revs
  # A range git cannot resolve must fail, not check zero commits and pass.
  revs=$(git rev-list "$1..$2") || { echo "::error::cannot list $1..$2"; return 1; }
  for c in $revs; do
    if ! git rev-parse -q --verify "$c^2" >/dev/null &&
       ! git log -1 --format=%s "$c" | grep -Eq "$type"; then
      echo "::error::${c:0:7} subject is not a Conventional Commit"; fail=1
    fi
    if git log -1 --format=%B "$c" | grep -Eiq "$bad"; then
      echo "::error::${c:0:7} message carries AI attribution"; fail=1
    fi
  done
  return $fail
}

# Positive and negative controls in a throwaway repo: fails if a pattern is
# dropped or loosened.
self_test() {
  local dir rc=0 msg base side
  dir=$(mktemp -d)
  g() { git -C "$dir" -c user.name=t -c user.email=t@t commit -q --allow-empty "$@"; }
  git -C "$dir" init -q
  g -m 'chore: root'; base=$(git -C "$dir" rev-parse HEAD)
  g -m 'feat: side'; side=$(git -C "$dir" rev-parse HEAD)
  expect() { # expect <0 pass|1 fail> <message> [merge]: [merge] merges side with <message>
    git -C "$dir" checkout -q --detach "$base"
    if [ -n "${3:-}" ]; then
      g -m 'feat: main'
      git -C "$dir" -c user.name=t -c user.email=t@t merge -q --no-ff "$side" -m "$2"
    else
      g -m "$2"
    fi
    (cd "$dir" && check "$base" HEAD >/dev/null); local got=$?
    [ $((got != 0)) -eq "$1" ] || { echo "self-test: want $1, got $got for: $2"; rc=1; }
  }
  expect 0 'feat(api): add a thing'
  expect 0 'fix!: break a thing'
  expect 0 'Revert "feat: add a thing"'
  expect 1 'add a thing'
  expect 1 'fixup! feat: add a thing'
  for msg in 'noreply@anthropic.com' 'https://Claude.ai/code/x' 'Generated With a tool' \
             'Co-Authored-By: Claude <x@y>' 'co-authored-by: someone at Anthropic'; do
    expect 1 "$(printf 'feat: ok\n\n%s' "$msg")"
  done
  expect 0 'Merge side' merge
  expect 1 "$(printf 'Merge side\n\nClaude-Session: https://claude.ai/code/x')" merge
  # An unresolvable range must fail rather than check nothing.
  if (cd "$dir" && check no-such-ref HEAD >/dev/null 2>&1); then
    echo "self-test: an unresolvable range passed"; rc=1
  fi
  rm -r "$dir"
  [ $rc -eq 0 ] && echo "self-test: ok"
  return $rc
}

if [ "${1:-}" = --self-test ]; then self_test; exit; fi
[ $# -eq 2 ] || { echo "usage: $0 BASE HEAD | --self-test" >&2; exit 2; }
check "$1" "$2"
