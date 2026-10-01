#!/usr/bin/env bash
# Checks the docs the way a reader would trip over them: a `#L` link past the
# end of its file, and a mermaid block GitHub cannot draw. Relative links and
# heading anchors are lychee's job (see .github/workflows/docs.yml).
#
#   scripts/docs-check.sh              line anchors + mermaid
#   DOCS_BASE=origin/main scripts/docs-check.sh
#                                      also warn about docs that link into code
#                                      changed since DOCS_BASE
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd -P)
failed=0

docs=$(git ls-files -co --exclude-standard -- '*.md' ':!docs/design/**' ':!**/node_modules/**')

# Repo-relative path of a link target, or nothing when its directory is missing.
resolve() {
	(cd "$(dirname "$1")" 2>/dev/null && cd "$(dirname "$2")" 2>/dev/null &&
		abs="$(pwd -P)/$(basename "$2")" && printf '%s' "${abs#"$ROOT"/}")
}

# Every [text](path#Lnn) links, one per line as doc:line:target:last-line.
line_links() {
	for doc in $docs; do
		# Links inside fenced code are examples, not links.
		awk '/^[[:space:]]*```/ { fenced = !fenced; next }
			!fenced { s = $0
				while (match(s, /\]\([^)#]*#L[0-9][-0-9L]*\)/)) {
					print FNR ":" substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }' "$doc" |
		while IFS= read -r hit; do
			link=${hit#*](}
			link=${link%)}
			# A permalink pins its own lines; only paths in this tree are checked.
			case $link in http://* | https://*) continue ;; esac
			target=${link%%#*}
			last=${link##*L}
			printf '%s:%s:%s:%s\n' "$doc" "${hit%%:*}" "$(resolve "$doc" "${target%\?plain=1}")" "$last"
		done
	done
}
links=$(line_links)

while IFS=: read -r doc line target last; do
	[ -z "$doc" ] && continue
	if [ -z "$target" ] || [ ! -f "$target" ]; then
		printf '%s:%s: link target does not exist\n' "$doc" "$line"
		failed=1
	elif [ "$last" -gt "$(wc -l <"$target")" ]; then
		printf '%s:%s: %s has %s lines, link asks for %s\n' "$doc" "$line" "$target" "$(wc -l <"$target" | tr -d ' ')" "$last"
		failed=1
	fi
done <<<"$links"

# A line shift is not provably wrong, so it can only be flagged.
if [ -n "${DOCS_BASE:-}" ]; then
	for file in $(git diff --name-only "$DOCS_BASE"...HEAD -- ':!*.md'); do
		while IFS=: read -r doc line target _; do
			[ "$target" = "$file" ] &&
				printf '::warning file=%s,line=%s::links into %s, which this change edits; recheck the line numbers\n' "$doc" "$line" "$file"
		done <<<"$links"
	done
fi

# mermaid-cli renders every block of a markdown file with one browser.
with_mermaid=$(grep -l '^```mermaid' $docs 2>/dev/null)
if [ -n "$with_mermaid" ]; then
	out=$(mktemp -d)
	trap 'rm -rf "$out"' EXIT
	printf '{"args":["--no-sandbox"]}' >"$out/puppeteer.json"
	for doc in $with_mermaid; do
		if ! msg=$(npx -y @mermaid-js/mermaid-cli@11.17.0 -q -p "$out/puppeteer.json" \
			-i "$doc" -o "$out/$(echo "$doc" | tr / _)" 2>&1); then
			printf '%s: mermaid does not parse\n%s\n' "$doc" "$msg"
			failed=1
		fi
	done
fi

exit $failed
