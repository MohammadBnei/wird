#!/bin/sh
# Writes ~/.config/wird/agent.env from Infisical (project infra-bootstrap-1-ge1,
# env dev, path /) without printing a secret. umask sets the mode before the
# file exists. Run again after a rotation or a recreated provider.
set -eu
get() {
  infisical secrets get "$1" --plain \
    --projectId=8a3fa54f-be22-488a-bf51-55158f65c0f2 \
    --env=dev --path=/ --domain=https://infisical.bnei.dev
}
mkdir -p "$HOME/.config/wird"
(
  umask 077
  # The id is authentik's generated one, read rather than committed: it
  # changes whenever the provider is recreated.
  id=$(get WIRD_ADMIN_OIDC_CLIENT_ID)
  cs=$(get WIRD_ADMIN_OIDC_CLIENT_SECRET)
  sa=$(get WIRD_AGENT_AUTHENTIK_TOKEN)
  [ -n "$id" ] && [ -n "$cs" ] && [ -n "$sa" ] || { echo "a value came back empty" >&2; exit 1; }
  {
    echo "export WIRD_ADMIN_URL=https://wird-admin.bnei.dev"
    echo "export WIRD_ADMIN_CLIENT_ID=$id"
    printf "export WIRD_ADMIN_CLIENT_SECRET='%s'\n" "$cs"
    printf "export WIRD_AGENT_AUTHENTIK_TOKEN='%s'\n" "$sa"
  } > "$HOME/.config/wird/agent.env.tmp"
  mv "$HOME/.config/wird/agent.env.tmp" "$HOME/.config/wird/agent.env"
)
ls -l "$HOME/.config/wird/agent.env" | cut -c1-10
