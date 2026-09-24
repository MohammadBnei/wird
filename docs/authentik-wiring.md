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

## What the client now does, and what was proved

**It sends the ID token.** Trap 1 was settled by experiment rather than by
reading a response object, on 2026-09-24, against the local stub with the real
`server/cmd/api` in front of it (`API_ADDR=:8085`, the default stub issuer):

```
POST /v1/sync, Authorization: Bearer <id_token>      -> 200 {"results":[]}
POST /v1/sync, Authorization: Bearer <access_token>  -> 401 {"error":"token rejected"}
```

and in the server's log, the reason in full:

```
token refused err="oidc: expected audience \"wird\" got [\"default\"]"
```

The stub's ID token carries `aud` = the client id and its access token carries
`aud: default`; Authentik's own access token audience is a provider setting
nobody has looked at. Either way the client does not depend on it:
`app/lib/data/auth.dart` stores and sends the ID token and never reads
`access_token`, and `app/test/data/auth_test.dart` fails if that ever changes.

`AuthHeader` is the only place a token exists. A 401 mid-flush refreshes once
and retries the same request; if that cannot be done the error is passed on as
the `DioException` it already is, which `syncNow` reads as "never reached the
server" — the queue keeps every op, spends no attempt and parks nothing. A
refusal of the *refresh token* (a 400 from the token endpoint) is the only
answer that signs the reader out, because it is the only one that will not
start working again.

**One thing the deployment must carry**: the API defaults to
`OIDC_AUDIENCE=wird`, and an Authentik ID token's `aud` is the client id. Set
`OIDC_AUDIENCE=Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro` wherever the API runs,
or every token this client sends is refused for the audience it carries.

**And one thing nobody knows yet**: `syncOrigin` in `app/lib/data/flush.dart`
still defaults to `https://wird.bnei.dev`, which is the host in the registered
redirect. On 2026-09-24 that host resolved and answered Go's bare `404 page not
found` to `/v1/sync`, `/v1/changes` and `/healthz`, so the API is not behind it
today. It is a `--dart-define` (`WIRD_ORIGIN`), so a build can say otherwise
without a release.

## Verifying it against the real Authentik, in one sitting

Nobody has done an interactive sign-in against `authentik.bnei.dev` yet. These
steps do it, and settle trap 1 and trap 2 on the real issuer while they are at
it. Ten lines of shell and one browser tab.

1. Open this address in a browser, sign in as yourself, and let it land on the
   callback. The page will 404 — `wird.bnei.dev` serves no API yet — which does
   not matter: what is wanted is the address bar.

   ```
   https://authentik.bnei.dev/application/o/authorize/?response_type=code&client_id=Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro&redirect_uri=https%3A%2F%2Fwird.bnei.dev%2Fauth%2Fcallback&scope=openid%20offline_access%20email%20profile&state=check&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256
   ```

   The challenge above is RFC 7636's own example pair, which is public and fine
   for one manual check and for nothing else.

2. Copy the `code` out of the address bar into `CODE`, and trade it for tokens:

   ```bash
   CODE=...
   curl -s -X POST https://authentik.bnei.dev/application/o/token/ \
     -d grant_type=authorization_code -d "code=$CODE" \
     -d client_id=Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro \
     -d redirect_uri=https://wird.bnei.dev/auth/callback \
     -d code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk > /tmp/t.json
   ```

   An `invalid_client` here means the provider is not configured as a public
   client, and that is an infra-bootstrap change, not a change in this repo.

3. Read the two tokens' claims. This answers trap 1's `aud` question and trap
   2's `groups` question in one look:

   ```bash
   python3 - <<'PY'
   import base64, json
   t = json.load(open('/tmp/t.json'))
   for k in ('id_token', 'access_token'):
       p = t[k].split('.')[1]; p += '=' * (-len(p) % 4)
       print(k, json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
   PY
   ```

   Expect `aud` on the ID token to be the client id. If `groups` is absent from
   it, the admin dashboard will 403 everybody until the property mapping is
   added in infra-bootstrap.

4. Point a local API at the real issuer and the audience the tokens actually
   carry, and send it each of the two tokens:

   ```bash
   docker compose up -d postgres
   OIDC_ISSUER=https://authentik.bnei.dev/application/o/wird/ \
   OIDC_AUDIENCE=Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro \
   API_ADDR=:8085 go run ./server/cmd/api &
   for k in id_token access_token; do
     printf '%s -> ' "$k"
     curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8085/v1/sync \
       -H "Authorization: Bearer $(jq -r .$k /tmp/t.json)" \
       -H 'content-type: application/json' -d '{"ops":[]}'
   done
   ```

   The recorded answer to beat: `id_token -> 200`, `access_token -> 401`. If it
   comes back the other way round, the provider issues JWT access tokens
   audienced to this client, and the decision in `auth.dart` is still safe —
   the ID token is the one go-oidc's `Verify` is written for.

5. Now the app itself. Open **Settings → ACCOUNT → Sign in** and follow what
   the panel says: the address goes on the clipboard, you open it in a browser,
   and you paste back the address it sends you to. The panel should then read
   `Signed in as <you>`. Leave the app open while you are in the browser — the
   PKCE verifier is held in memory until you come back.

   ```bash
   cd app && fvm flutter run -d macos \
     --dart-define=WIRD_ORIGIN=http://localhost:8085 \
     --dart-define=WIRD_REDIRECT=https://wird.bnei.dev/auth/callback
   ```

   The redirect is overridden because the built macOS app registers
   `dev.bnei.wird://` as its own scheme, so a browser sent there launches the
   app instead of showing you an address to copy. The default stays
   `dev.bnei.wird://`, which is what the deep-link implementation will want.

6. Last, the thing this was all for: mark a set understood while signed in, put
   the app in the background and bring it back, and confirm the write arrives.
   From the server side that is one query.

   ```bash
   psql postgres://wird:wird@localhost:5432/wird -c 'SELECT count(*) FROM ayah_understood'
   ```

   If it is still zero, read the API's log: `token refused` names the audience
   it got, and anything else means the flush never reached it.
