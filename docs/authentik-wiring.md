# Wiring Wird to Authentik

Checked live 2026-09-24 against
`https://authentik.bnei.dev/application/o/wird/.well-known/openid-configuration`.
Everything below is what the discovery document actually says, not what the
provider usually does.

## What is there

| | |
| --- | --- |
| issuer | `https://authentik.bnei.dev/application/o/wird/` |
| authorization | `https://authentik.bnei.dev/application/o/authorize/` |
| token | `https://authentik.bnei.dev/application/o/token/` |
| jwks | `https://authentik.bnei.dev/application/o/wird/jwks/` |
| end session | `https://authentik.bnei.dev/application/o/wird/end-session/` |
| PKCE | `S256` and `plain` |
| scopes | `openid`, `offline_access`, `profile`, `email` |
| grants | `authorization_code`, `refresh_token`, and four others |

client_id `Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro`, a public client.
Redirects `dev.bnei.wird://` and `https://wird.bnei.dev/auth/callback`.

The server needs `OIDC_ISSUER` set to the issuer above and nothing else
changed. `server/internal/auth/auth.go` discovers the issuer and verifies
against its JWKS; it mints no tokens and knows nothing about which provider it
is talking to. That was the point of writing it that way.

## The two traps

### 1. An access token is not an ID token

`auth.go` builds `provider.Verifier(&oidc.Config{ClientID: audience})` and
calls `Verify`, which is go-oidc's **ID token** path: it checks that `aud`
contains the client id.

Authentik issues an access token as well, and the obvious client code sends
*that* as the bearer. Whether it verifies depends on how the provider was
configured to sign and audience access tokens, and the failure is a flat 401
with "token rejected" in the log and no hint about which of the two tokens
arrived.

**Decide it explicitly and write it in the client**: send the ID token, or
configure Authentik to issue JWT access tokens carrying this client id in
`aud`. Do not let it be settled by whichever token the auth library returns
first from its response object.

The falsifiable check: sign in, send each of the two tokens to `/v1/sync`, and
record which is accepted. A round that has not done that has not wired auth, it
has written auth-shaped code.

### 2. `groups` is not in `scopes_supported`

The admin app authorises on membership of `platform-admins` — the same list
Grafana reads for `Admin` and ArgoCD for `role:admin`. That claim has to be in
the token, and the discovery document advertises only `openid`,
`offline_access`, `profile` and `email`.

Authentik supplies group membership through a **scope mapping**, which is
configured per provider and does not have to appear in `scopes_supported`. So
the claim may well be there — but nobody has looked, and an admin app that
reads a claim which is absent authorises nobody, or, if it is written the
careless way round, everybody.

**Get a real token and read its claims before writing the check.** If the claim
is absent, the fix is in the Authentik provider's property mappings
(infra-bootstrap), not in this repo.

**Resolved on the safe side, 2026-09-24.** `server/cmd/adminweb/auth.go` reads
the claim into a `[]string` and asks `slices.Contains`. An absent claim
decodes to nil, nil contains nothing, and the request gets 403. So the
failure mode if the mapping is missing is that **nobody can open the
dashboard**, not that everybody can — which is the half of this that had to be
got right before anyone could sleep on it.

What remains is a deployment check rather than a correctness one: sign in once
and confirm the token really carries `groups`, and if it does not, add the
property mapping in infra-bootstrap. Until that is done, expect 403 rather than
a way in.

## What the client has to be, structurally

Wird works entirely offline and the whole reading loop is local. So:

- **Signing in is optional.** Being signed out blocks nothing. It enables sync.
- **Signing out must not delete local progress.** A reader who signs out has
  not asked to forget what they have understood, and treating those as the same
  act destroys data over a misunderstanding.
- **The token attaches at the Dio interceptor**, which is where `SyncApi`
  already takes its client. No screen and no repository should know a token
  exists.
- **A 401 mid-flush is a transient fault, not a refusal.** `classify()` parks a
  refusal permanently. An expired token that classifies as refused
  dead-letters every queued write a reader made while offline.

That last one is the expensive mistake available here, and it is the same shape
as the set-id namespace bug: correct-looking code on both sides, silent
permanent data loss in the middle.
