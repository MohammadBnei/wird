#!/bin/sh
# pull.sh <dir> — writes <dir>/reports.json (status new) and <dir>/verdicts.json,
# then prints a one-line summary. <dir> must be outside the repo.
set -eu
dir=${1:?usage: pull.sh <dir outside the repo>}
. "$(dirname "$0")/lib.sh"
mkdir -p "$dir"
curl -sf -H "Authorization: Bearer $TOKEN" "$WIRD_ADMIN_URL/reports.json?status=new" > "$dir/reports.json"
curl -sf -H "Authorization: Bearer $TOKEN" "$WIRD_ADMIN_URL/verdicts.json" > "$dir/verdicts.json"
jq -r '"reports new: \(.reports|length), truncated: \(.truncated)"' "$dir/reports.json"
jq -r '"verdict rows: \(length), roots bad on current text: \([.[]|select(.bad_on_current>0)]|length)"' "$dir/verdicts.json"
