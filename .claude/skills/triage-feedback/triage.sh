#!/bin/sh
# triage.sh <report id> <category> <status> [issue url]
# Writes all three fields (an omitted one is cleared). issued needs the url.
# Prints the HTTP status: 204 done, 400 bad input, 404 report gone.
set -eu
id=${1:?usage: triage.sh <id> <category> <status> [issue_url]}
category=${2:?category}
status=${3:?status}
url=${4:-}
. "$(dirname "$0")/lib.sh"
body=$(jq -n --arg c "$category" --arg s "$status" --arg u "$url" '{category:$c,status:$s,issue_url:$u}')
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  "$WIRD_ADMIN_URL/reports/$id" -d "$body"
