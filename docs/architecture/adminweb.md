# Admin web

> The operations view: a separate Go binary, gated on an Authentik group, that shows totals, reports and sense verdicts, writes a report's triage, and exports both for the maintainer's agent. Level L1 · Parent [Overview](../README.md) · Children none

## Black box

Admin web is one page for operators, plus two exports and one write. The page shows how many readers there are, how many sets have been prayed, how many writes failed or were parked, the reports readers chose to send, and how readers judged each root's sense. An operator can file each report under a category and say what became of it. It never shows what one reader understood, kept or prayed.

It is a separate binary from `wird-api`. It reads the same Postgres directly and does not call the API, and it never runs migrations: the API alone does. Only members of Authentik's `platform-admins` group get in, and the token proving that is checked here, not trusted from a proxy header.

The maintainer works with a coding agent. The agent signs in as a service account in the same group, pulls the exports, drafts one GitHub issue per finding in its own words, and writes the triage back. Reports never reach the public tracker as quotes.

| In | Out | Depends on |
|---|---|---|
| An operator's browser, through the cluster's forwardAuth proxy | One HTML page: totals, corpus versions, reports with their triage, sense verdicts | Postgres, the same database as `wird-api` |
| The agent, with a service account's token | `reports.json` and `verdicts.json` | Authentik, for the signing keys and the group claim |
| A triage for one report: category, status, issue link | The report's triage, stored | The Nocturne stylesheet, read from disk at start |
| A signed token in `X-authentik-jwt` (what the outpost forwards), `X-Forwarded-Access-Token` or `Authorization: Bearer` | 401 for no or bad token, 403 outside the group | |

```mermaid
flowchart LR
  op([Operator])
  agent([Maintainer's agent])
  proxy["forwardAuth proxy"]
  admin["Admin web"]
  idp["Authentik"]
  pg[("Postgres")]
  gh["GitHub issues<br/>public"]
  api["wird-api"]
  app["Wird app"]

  op --> proxy -->|"signed token"| admin
  agent -->|"service account token"| admin
  admin -->|"signing keys"| idp
  admin -->|"totals, reports, verdicts<br/>triage writes"| pg
  agent -->|"paraphrased issue,<br/>after the maintainer confirms"| gh
  app --> api --> pg
```

### Deployment

Every release builds a `wird-adminweb` image next to `wird-api`, from the same Dockerfile and the same commit, and bumps its tag in `helm/adminweb-values.yaml` ([Deploy](deploy.md#4-one-binary-per-image)). That values file does nothing yet. It is registered in the infrastructure repo only after four things exist there: a forwardAuth proxy provider whose client id is this view's audience and which forwards the operator's token, the `groups` claim, the agent's service account, and a database role that can only read the dashboard and write a report's triage ([values file header](../../helm/adminweb-values.yaml#L1-L10)). Until then the page would refuse everyone.

## White box

```mermaid
flowchart TB
  start["main<br/>pool without migrating, audience,<br/>HS256 or JWKS verifier, stylesheet"]
  mux["routes"]
  health["GET /healthz"]
  css["GET /styles.css"]
  gate["operators<br/>verify token, need platform-admins<br/>Cache-Control: no-store"]
  cop["CrossOriginProtection"]
  dash["GET /<br/>dashboard"]
  rj["GET /reports.json"]
  vj["GET /verdicts.json"]
  tri["POST /reports/{id}<br/>triage"]
  s1["store.CorpusVersion"]
  s2["store.Health<br/>counts only"]
  s3["store.Reports<br/>verdicts left out"]
  s4["store.SenseVerdicts<br/>per root and language"]
  s5["store.TriageReport<br/>retried once"]
  tmpl["dashboard.html<br/>html/template"]

  start --> mux
  mux --> health
  mux --> css
  mux --> gate
  mux --> cop --> gate
  gate -->|"401 / 403"| stop(["refused"])
  gate --> dash & rj & vj & tri
  dash --> s1 & s2 & s3 & s4
  s1 & s2 & s3 & s4 --> tmpl
  rj --> s3
  vj --> s4
  tri --> s5
```

### 1. Start-up: a pool, an issuer, an audience, a stylesheet

The binary opens a database pool and pings it, but does not migrate. Goose takes no lock, so two binaries migrating the same database at once would race. The API migrates; this reads the schema it left.

```go
	// store.New, not store.Open: Open runs the migrations, and goose takes no
	// lock, so two binaries migrating the same database at once is a race. The
	// api is the one that migrates; this reads the schema it left.
	pool, err := pgxpool.New(ctx, env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"))
	if err == nil {
		err = pool.Ping(ctx)
	}
```

[main.go:30-36](../../server/cmd/adminweb/main.go#L30-L36)

Then it builds the token verifier. In production the audience is `OIDC_CLIENT_ID`, the proxy provider's client id, and the signing key is `OIDC_CLIENT_SECRET`: Authentik's proxy provider has no signing key of its own and signs HS256 with its client secret. Both come from the deployment secret, because the provider's id is generated by Authentik and cannot be committed. Without a secret, as with the local OIDC stub, the binary discovers the issuer and checks its published keys, like `wird-api`, against the audience `OIDC_AUDIENCE`, `wird-admin` by default ([main.go:49](../../server/cmd/adminweb/main.go#L49)).

```go
	var verifier *oidc.IDTokenVerifier
	if secret := os.Getenv("OIDC_CLIENT_SECRET"); secret != "" {
		verifier = clientSecretVerifier(issuer, audience, secret)
	} else {
		provider, err := oidc.NewProvider(ctx, issuer)
		if err != nil {
			log.Error("issuer unavailable", "issuer", issuer, "err", err)
			os.Exit(1)
		}
		verifier = provider.Verifier(&oidc.Config{ClientID: audience})
	}
```

[main.go:54-64](../../server/cmd/adminweb/main.go#L54-L64)

It reads the vendored Nocturne stylesheet and refuses to start without it ([main.go:66-73](../../server/cmd/adminweb/main.go#L66-L73)). The stylesheet is [`docs/design/nocturne-styles.css`](../design/nocturne-styles.css), the one the app's theme is tested against, so the page cannot drift from the design system. The image carries a copy and points `NOCTURNE_CSS` at it. It listens on `ADMIN_ADDR`, `:8081` by default ([main.go:75](../../server/cmd/adminweb/main.go#L75)).

### 2. Six routes, four of them gated

```go
	gated := func(h http.HandlerFunc) http.Handler { return noStore(operators(verifier, log, h)) }
	mux.Handle("GET /{$}", gated(s.dashboard))
	mux.Handle("GET /reports.json", gated(s.reportsJSON))
	mux.Handle("GET /verdicts.json", gated(s.verdictsJSON))
	// The one write. A signed-in operator's browser carries the token the
	// proxy forwards, so a page elsewhere that posts here would be filing
	// reports in their name; Go's own check refuses a cross-origin POST before
	// the token is even looked at.
	mux.Handle("POST /reports/{id}", http.NewCrossOriginProtection().Handler(gated(s.triage)))
```

[main.go:99-107](../../server/cmd/adminweb/main.go#L99-L107)

| Route | Gate | Answers |
|---|---|---|
| `GET /healthz` | none | 200 |
| `GET /styles.css` | none | the Nocturne stylesheet |
| `GET /` | group | the dashboard |
| `GET /reports.json` | group | written reports, newest first; `?status=new` narrows them |
| `GET /verdicts.json` | group | the sense verdict tally |
| `POST /reports/{id}` | cross-origin check, then group | 204 for JSON, a redirect to `/` for the form |

Every gated answer carries `Cache-Control: no-store` ([main.go:111-116](../../server/cmd/adminweb/main.go#L111-L116)). A page or export kept by a proxy or a shared browser would be reports read by whoever opens that cache next.

### 3. The group gate

The proxy handles the login. Admin web makes the decision. authentik's outpost forwards the operator's token as `X-authentik-jwt`, and lets an agent's `Authorization: Bearer` through without a login redirect. Whichever header carries it, the token goes through the same verifier, so a header set by hand gets a 401. The outpost's unsigned `X-authentik-groups` is never read ([auth.go:70-89](../../server/cmd/adminweb/auth.go#L70-L89)).

authentik's proxy provider has no signing key and cannot be given one, so it signs HS256 with its client secret. authentik also generates the provider's client id and secret and ignores any declared, so neither is committed: both reach adminweb from the deployment's secret, the id as `OIDC_CLIENT_ID` (the audience) and the secret as `OIDC_CLIENT_SECRET`. adminweb checks every token against that secret, with the same issuer, audience and expiry checks as the published-key path the local stub uses ([auth.go:14-36](../../server/cmd/adminweb/auth.go#L14-L36)). Only HS256 is parsed, so a token whose header names another algorithm is refused, and a token signed with another provider's secret does not verify. The provider always allows the password grant, so any directory user can mint a valid token for this audience: the group check is what keeps them out. A valid token without the group gets a 403.

```go
		token, err := verifier.Verify(r.Context(), raw)
		if err != nil {
			log.Info("token refused", "err", err)
			http.Error(w, "token rejected", http.StatusUnauthorized)
			return
		}
		var claims struct {
			Groups []string `json:"groups"`
		}
		if err := token.Claims(&claims); err != nil || !slices.Contains(claims.Groups, operatorGroup) {
			log.Info("not an operator", "group", operatorGroup)
			http.Error(w, "this page is for "+operatorGroup, http.StatusForbidden)
			return
		}
```

[auth.go:52-65](../../server/cmd/adminweb/auth.go#L52-L65)

There is no admin table in Wird. An operator is whoever Authentik says is in `platform-admins` ([auth.go:38-43](../../server/cmd/adminweb/auth.go#L38-L43)). A token with no `groups` claim contains nothing, so it gets a 403. That is the safe way round.

### 4. The page reads four things, each on its own

Each section is read separately. A section that could not be read says so, instead of showing an empty list that looks like "nothing yet". The report list leaves the sense verdicts out, because hundreds of one-word thumbs would bury the reports somebody wrote out. When there are more than 200 reports, the page says the export has the rest.

```go
	page.Reports, page.ReportsCut, err = s.db.Reports(r.Context(),
		store.ReportFilter{ExcludeVerdicts: true, Limit: store.ReportPage})
	if err == nil {
		page.ReportsOK = true
	} else {
		s.log.Error("reports", "err", err)
	}
	if page.Verdicts, err = s.db.SenseVerdicts(r.Context()); err == nil {
		page.VerdictsOK = true
	} else {
		s.log.Error("verdicts", "err", err)
	}
```

[main.go:156-167](../../server/cmd/adminweb/main.go#L156-L167) · corpus and health above it [main.go:144-153](../../server/cmd/adminweb/main.go#L144-L153)

Each report row shows the build, the screen, the corpus and sense versions, the language and the sense hash, and a small triage form ([dashboard.html:94-124](../../server/cmd/adminweb/dashboard.html#L94-L124)). The page is rendered by `html/template` from an embedded file ([main.go:287-297](../../server/cmd/adminweb/main.go#L287-L297)), which links the stylesheet served in step 2 ([dashboard.html:7](../../server/cmd/adminweb/dashboard.html#L7)).

### 5. Sense verdicts are counted, not listed

A thumb on a sense arrives as a report whose body is `sense good: <root>` or `sense bad: <root>`, with the language it was read in and a hash of the sentence judged ([Senses in the app](app/senses.md#8-the-readers-verdict-on-a-sense)). One condition, `isVerdict`, says which reports are verdicts:

```go
const isVerdict = `r.kind = 'improvement'
   AND r.body IN ('sense good: ' || s.root_letters, 'sense bad: ' || s.root_letters)`
```

[admin.go:148-149](../../server/internal/store/admin.go#L148-L149)

It is applied once, by the report sweep in `wird-api`, when a report first arrives. The sweep stores the matching root in the report's `verdict_root`, judged against the roots served at that moment, and carries it unchanged on every later sweep ([sync.go:569-588](../../server/internal/store/sync.go#L569-L588)). The report list and the export leave out every report with a `verdict_root`, and the tally counts exactly those, so no report can fall between them ([admin.go:173](../../server/internal/store/admin.go#L173)).

The tally groups them by root and language:

```go
var senseVerdictsSQL = `
SELECT r.verdict_root, r.locale,
       count(*) FILTER (WHERE r.body = 'sense good: ' || r.verdict_root) AS good,
       count(*) FILTER (WHERE r.body = 'sense bad: ' || r.verdict_root) AS bad,
       count(*) FILTER (WHERE r.body = 'sense bad: ' || r.verdict_root AND r.sense_hash = ` +
	senseHashSQL(`CASE WHEN r.locale = 'fr' THEN s.sense_fr ELSE s.sense_en END`) + `) AS bad_on_current
  FROM reports r
  LEFT JOIN root_senses s ON s.root_letters = r.verdict_root
 WHERE r.verdict_root IS NOT NULL
 GROUP BY r.verdict_root, r.locale
 ORDER BY bad_on_current DESC, bad DESC, r.verdict_root, r.locale`
```

[admin.go:255-265](../../server/internal/store/admin.go#L255-L265)

Four choices matter here.

- **A verdict is the whole body, for a root of ours.** A body that only starts like a verdict, such as a reader typing "sense bad: the French for this is wrong", is a written report. It stays in the list and the export, and the tally never counts it.
- **The root shown is ours.** It is a `root_senses` key, copied by the sweep, not the body's text. A body is whatever a stranger typed, so a tally keyed on it would be a list of what strangers typed.
- **A verdict stays a verdict.** Because the root is settled on arrival, a later reseed that drops a root does not turn its votes back into reports. They stay counted and out of the list, with `bad_on_current` at 0, since the root has no current text.
- **`bad_on_current` counts only the text served today.** The server hashes its own sentence the way the app does, and compares. A bad verdict on a sentence since redrafted drops out, so the root at the top is one whose current text readers judge wrong.

A report's `locale` is `en`, `fr` or empty. The API blanks any other value on arrival, so the tally cannot grow a row for every string a device invents ([Sync endpoints](api/sync-endpoints.md#5-apply-by-kind)).

### 6. Triage: the one write

A triage is three values written together: a category (`sense`, `bug`, `ux`, `content`, `request`, `noise`, or none), a status (`new`, `issued`, `dismissed`), and an optional link to a GitHub issue. The page sends it as a form; the agent sends JSON, and an unknown key is a 400. Each value is checked against the column's own rule first, so a bad value is answered with its reason rather than read as the server failing ([main.go:226-240](../../server/cmd/adminweb/main.go#L226-L240)). The issue link must start with `https://github.com/`, because it is drawn as a link on the operator's page. One rule is stricter than the columns: a report marked `issued` must name its issue, or the request is a 400. The id in the path is parsed as a UUID and passed to the store in its canonical form, because the parser accepts spellings Postgres refuses ([main.go:263-269](../../server/cmd/adminweb/main.go#L263-L269)).

The store retries the write once, and the retry is not a hedge:

```go
func (s *Store) TriageReport(ctx context.Context, id, category, status, issueURL string) error {
	for range 2 {
		tag, err := s.pool.Exec(ctx, `
			UPDATE reports SET category = nullif($2, ''), status = $3, issue_url = nullif($4, '')
			 WHERE id = $1`, id, category, status, issueURL)
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			return nil
		}
	}
	return ErrReportNotFound
}
```

[admin.go:213-226](../../server/internal/store/admin.go#L213-L226)

The report sweep in `wird-api` deletes every report and writes it back under the same id, in one statement ([Sync endpoints](api/sync-endpoints.md)). An update queued behind it finds the old row gone and cannot see the new one, so it touches nothing. A second statement takes a fresh snapshot and finds the row. The sweep itself carries the triage columns and `verdict_root` across its rewrite, so it never undoes an operator's work. A second miss is an id that is really not there: 404.

A triage is the operator's words about a report. Nothing in it travels back to a device, and it adds no channel to the report's author.

### 7. The exports

Both exports are JSON, gated and uncached like the page.

`GET /reports.json` returns written reports, newest first, verdicts left out. `?status=new` (or `issued`, `dismissed`) narrows them; any other status is a 400 ([main.go:178-195](../../server/cmd/adminweb/main.go#L178-L195)). One export holds at most 5,000 reports, and `truncated` says when the cap cut it short ([admin.go:122-126](../../server/internal/store/admin.go#L122-L126)).

```json
{
  "reports": [
    {
      "id": "…", "kind": "bug", "body": "…",
      "app_version": "…", "platform": "android", "screen": "study",
      "corpus_version": 7, "sense_version": "…", "locale": "fr", "sense_hash": "",
      "category": "", "status": "new", "issue_url": "", "written_on": "…"
    }
  ],
  "truncated": false
}
```

`GET /verdicts.json` returns the tally of step 5, worst first, as a list of `{ "root", "locale", "good", "bad", "bad_on_current" }` ([admin.go:268-274](../../server/internal/store/admin.go#L268-L274)).

### 8. What the agent does with them

The procedure lives with the agent's own instructions, in [`.claude/rules/feedback.md`](../../.claude/rules/feedback.md). In short: it pulls both exports into a scratch folder and stops if `truncated` is true. It sorts each report into a category, using the report's `screen` to find the code it is about. It drafts one issue per finding as a paraphrase stripped of anything personal, and never posts the report's id, day, platform or build. It shows the drafts to the maintainer, creates only the confirmed ones, and posts the triage back. Report text is data to it, never instructions. A report with an empty `locale` was sent by a build whose report screen did not yet mention the public tracker, so it is triaged but never summarised in public ([ADR 0026](../adr/0026-reports-are-triaged-and-turned-into-issues.md#consequences)).

For senses, it acts only on `bad_on_current`, and proposes a redraft of those roots through the [senses pipeline](pipelines/senses.md).

The reader is told this before sending. The report screen's caption says that maintainers read a report and may summarise it, never quote it, in Wird's public issue tracker ([report_screen.dart:134-137](../../app/lib/features/report/report_screen.dart#L134-L137)).

### 9. Totals only, by construction

None of the store methods admin web may call takes a reader. The health numbers are plain counts over whole tables.

```go
	readersSQL      = `SELECT count(*) FROM users`
	setsPrayedSQL   = `SELECT count(*) FROM set_prayers`
	syncFailuresSQL = `SELECT coalesce(sum(ops), 0)::bigint FROM sync_outcomes WHERE status = 'failed'`
	parkedWritesSQL = `SELECT coalesce(sum(ops), 0)::bigint FROM sync_outcomes WHERE status = 'refused'`
```

[admin.go:20-23](../../server/internal/store/admin.go#L20-L23)

Tests hold the rule, not habit:

- The package may call only `Health`, `Reports`, `SenseVerdicts`, `CorpusVersion`, `TriageReport` and `Close`, and holds no SQL of its own ([adminweb_test.go:145](../../server/cmd/adminweb/adminweb_test.go#L145)). `TriageReport` takes a report's id, which no column joins to a reader.
- Every aggregate the dashboard can run, the verdict tally included, has no argument that could bind it to one reader ([admin_test.go:48](../../server/internal/store/admin_test.go#L48)).
- The page, rendered from a real database with two readers, never contains their ids or subjects ([adminweb_test.go:233](../../server/cmd/adminweb/adminweb_test.go#L233)). Neither do the exports, and both are never cached ([adminweb_test.go:484](../../server/cmd/adminweb/adminweb_test.go#L484)).
- A valid token outside the group, and a token that cannot be proven, are both served nothing ([adminweb_test.go:80](../../server/cmd/adminweb/adminweb_test.go#L80), [adminweb_test.go:116](../../server/cmd/adminweb/adminweb_test.go#L116)). A triage posted from another site is refused ([adminweb_test.go:408](../../server/cmd/adminweb/adminweb_test.go#L408)).
- A verdict on a root Wird never wrote never reaches the tally, and a bad verdict on corrected text does not count against today's ([triage_test.go:78](../../server/internal/store/triage_test.go#L78), [triage_test.go:42](../../server/internal/store/triage_test.go#L42)).
- A reseed that drops a root leaves its votes counted and out of the list ([triage_test.go:100](../../server/internal/store/triage_test.go#L100)).
- A triage written while the sweep rewrites the table still lands, and the sweep keeps it ([triage_test.go:174](../../server/internal/store/triage_test.go#L174), [triage_test.go:234](../../server/internal/store/triage_test.go#L234)).
- A typed report that starts like a verdict stays in the list, and an unknown locale is blanked rather than refused ([triage_test.go:290](../../server/internal/store/triage_test.go#L290), [triage_test.go:270](../../server/internal/store/triage_test.go#L270)).
- The app and the server hash a sense the same way ([triage_test.go:312](../../server/internal/store/triage_test.go#L312)).

Reports carry no reader id, but ADR 0004 is precise about the limit: the page cannot attribute a report, while someone with `SELECT` on the database still can. That is why the view's database role is to be limited to what it reads and the triage it writes.

## Why it is this way

- [ADR 0004](../adr/0004-the-operations-view-behind-authentiks-group.md) — the group gate, forwardAuth with the token verified here, totals only, and Go with `html/template` and the Nocturne stylesheet.
- [ADR 0005](../adr/0005-deploying-the-api.md) — one binary per image; the operations view was first held back from deployment.
- [ADR 0026](../adr/0026-reports-are-triaged-and-turned-into-issues.md) — reports gain a language, a sense hash and a triage; verdicts are tallied, not listed; the view exports and writes; the agent turns reports into paraphrased issues; the view ships as its own image, inert until the infrastructure work is done.

## Go deeper

- [Auth](api/auth.md) — the readers' side of the same JWKS check.
- [API](api.md) — the other binary on the same database, and the one that migrates it.
- [Sync endpoints](api/sync-endpoints.md) — how a report arrives, and the sweep the triage has to survive.
- [Senses in the app](app/senses.md#8-the-readers-verdict-on-a-sense) — where a sense verdict comes from.
- [Deploy](deploy.md) — what is built and shipped.
- [Authentik wiring](../guides/authentik-wiring.md#2-groups-is-not-in-scopes_supported) — the `groups` claim, and what else the view waits for.
