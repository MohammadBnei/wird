# Sourced by pull.sh and triage.sh. Loads the agent's credentials and mints a
# one-hour token for the operations view. Never prints a secret.
ENV_FILE="$HOME/.config/wird/agent.env"
[ -r "$ENV_FILE" ] || { echo "no $ENV_FILE: run setup.sh first" >&2; exit 1; }
. "$ENV_FILE"

# client-credentials on the wird-admin proxy provider: the app-password token is
# the password, and the access_token that comes back is the Bearer.
mint() {
  curl -s https://authentik.bnei.dev/application/o/token/ \
    -d grant_type=client_credentials \
    -d client_id="$WIRD_ADMIN_CLIENT_ID" -d client_secret="$WIRD_ADMIN_CLIENT_SECRET" \
    -d username=wird-agent -d password="$WIRD_AGENT_AUTHENTIK_TOKEN" -d scope='openid profile' \
    | jq -r '.access_token // empty'
}
TOKEN=$(mint)
[ -n "$TOKEN" ] || { echo "authentik minted no token: check agent.env against Infisical" >&2; exit 1; }
