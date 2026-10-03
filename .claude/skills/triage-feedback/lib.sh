# Sourced by pull.sh and triage.sh. Loads the agent's credentials and mints a
# one-hour token for the operations view. Never prints a secret.
ENV_FILE="$HOME/.config/wird/agent.env"
[ -r "$ENV_FILE" ] || { echo "no $ENV_FILE: run setup.sh first" >&2; exit 1; }
. "$ENV_FILE"

# client-credentials on the wird-admin proxy provider: the app-password token is
# the password, and the access_token that comes back is the Bearer.
# Three failures, three messages: authentik unreachable, authentik refusing the
# credentials (its error body says which), and an answer that is not a token.
mint() {
  curl -sS --fail-with-body https://authentik.bnei.dev/application/o/token/ \
    -d grant_type=client_credentials \
    -d client_id="$WIRD_ADMIN_CLIENT_ID" -d client_secret="$WIRD_ADMIN_CLIENT_SECRET" \
    -d username=wird-agent -d password="$WIRD_AGENT_AUTHENTIK_TOKEN" -d scope='openid profile'
}
answer=$(mint) || {
  echo "authentik refused or was unreachable: ${answer:-no answer}" >&2
  echo "credentials refused → rerun setup.sh; unreachable → check the network" >&2
  exit 1
}
TOKEN=$(printf '%s' "$answer" | jq -r '.access_token // empty' 2>/dev/null || true)
[ -n "$TOKEN" ] || { echo "authentik answered without a token" >&2; exit 1; }

# get <path> — one export, or a message naming the path and the status. Only
# 200 is an export: a token the outpost does not accept comes back as a 302 to
# the login page, which curl counts as success, and 401/403 is adminweb
# refusing a token authentik issued (wird-agent not in platform-admins, or
# the client id moved).
get() {
  out=$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer $TOKEN" "$WIRD_ADMIN_URL$1") || {
    echo "adminweb unreachable for $1" >&2
    return 1
  }
  code=${out##*
}
  [ "$code" = 200 ] || {
    echo "adminweb answered $code for $1 (302: token not accepted by the outpost; 401/403: refused → setup.sh, check platform-admins)" >&2
    return 1
  }
  printf '%s' "${out%
*}"
}
