#!/bin/sh
# pull.sh <dir> — writes <dir>/reports.json (status new) and <dir>/verdicts.json,
# then prints a one-line summary. <dir> must be outside the repo.
set -eu
dir=${1:?usage: pull.sh <dir outside the repo>}
. "$(dirname "$0")/lib.sh"
mkdir -p "$dir"
# Fetched into variables first, so a refused request leaves the last good
# files in place instead of empty ones.
reports=$(get "/reports.json?status=new")
verdicts=$(get /verdicts.json)
printf '%s\n' "$reports" > "$dir/reports.json"
printf '%s\n' "$verdicts" > "$dir/verdicts.json"
jq -r '"reports new: \(.reports|length), truncated: \(.truncated)"' "$dir/reports.json"
jq -r '"verdict rows: \(length), roots bad on current text: \([.[]|select(.bad_on_current>0)]|length)"' "$dir/verdicts.json"
