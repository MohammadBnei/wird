## Part 1 — Architecture Decision

**Decision.** Flutter client (iOS + Android + tablet) against a Go + Postgres 18 backend,
Authentik OIDC, deployed into the existing ukubi-cluster by GitOps. The server is the
source of truth for **user state**; the client owns the corpus, generates its own sets, and
keeps a write outbox so the in-prayer screen never blocks on a socket.

**Context / problem.** Every screen reads a corpus (text, gloss, roots, morphology, audio
timings) too large to ship whole and too slow to fetch per tap. Screen `1b` runs mid-prayer,
hands-free, in rooms that usually have no signal.

**Quality attribute priority.** *In-prayer reliability wins over freshness.* When cache and
server disagree, the cache serves the prayer and reconciles afterwards. Second: cold-tap
latency on root lookup — `1a` → `3a` must feel instant, so it never touches the network.

**Constraints.**
- **The cluster exists and dictates the shape.** `MohammadBnei/infra-bootstrap` runs
  ukubi-cluster: ArgoCD GitOps, Authentik at `authentik.bnei.dev` (ADR-0039) configured by
  declarative blueprints, Postgres by pigsty with automatic failover (ADR-0029) and
  pgbackrest, secrets via Infisical. Wird deploys into that. Docker Compose is local dev only.
- **The Authentik client must be `client_type: public`.** Every existing blueprint
  (`-grafana`, `-argocd`, `-fleet`) is *confidential*, with a secret delivered through
  Infisical — right for server apps, wrong for a mobile binary that cannot keep a secret.
  Wird needs a public client, PKCE, custom-scheme redirect. New shape for this cluster ⇒ a
  review conversation, not a copy-paste. The repo's `.claude/skills/authentik-oidc` is the
  procedure.
- **Postgres 18 via pigsty**, confirmed `pg_version: 18`. Databases and roles are declared
  in `pigsty/pigsty.yml` (`pg_databases` / `pg_users`, behind pgbouncer) — so creating the
  `wird` database is a cluster change, not an app migration.
- Recitation audio is a v1 requirement and must survive going offline for the set about to
  be prayed.
- Scheherazade New must be bundled; platform fonts mangle Qur'anic diacritics.

**Alternatives considered.**

| Option | Why rejected |
| --- | --- |
| Expo / React Native | Viable; Flutter chosen by the user. One render pipeline keeps the `3a` dial identical on both platforms. |
| Native SwiftUI | Best mic path, but Android becomes a rewrite. |
| Web PWA | No dependable offline Arabic speech on iOS Safari, flaky wake-lock. Kills `1b`. |
| Whisper on-device | Better Arabic, but 75–150 MB model, battery, latency tuning. Open as the voice-follow engine if the platform recognisers disappoint; nothing depends on it. |
| Cloud streaming ASR | Streams worship audio off-device, and needs signal where there is none. |
| Fully bundled corpus (~150 MB+) | Rejected for the hybrid split: tafsir and lexicon prose are the bulk and are read rarely. |
| quran.com API at runtime | Every root tap a round trip; `1b` unusable offline. |
| Local-first with no server | Rejected — but note the first draft rejected it against a strawman ("local-first means no backup"). It does not. What we actually reject is *server-as-replica*; we want server-as-authority for user state, with the corpus local. |
| Online-only CRUD | A spinner mid-prayer is the one failure that matters. |

**Consequences (what we accept).**
- A build-time ETL and a bundled read-only SQLite asset are part of the release pipeline.
- Cache invalidation, an outbox, and a sync cursor are code we own, not framework features.
- `1b` advances on a tap by default. Voice-follow is an enhancement that may be unavailable
  on a given device, and its absence costs a convenience rather than a screen.
- Sharing Postgres with Authentik (see §0).

**Out of scope / deferred.** Multiple reciters; push notifications; sharing; memorisation
drills; Android-tablet layout; tafsir translations whose licence does not permit
redistribution inside an app bundle.

**Reversibility.** One-way: Flutter, the Postgres schema, Authentik as IdP, **and — after
launch — the bundled/fetched split** (changing it needs a release plus a cached-data
migration; the first draft wrongly called this two-way). Two-way: the ASR engine behind
`VoiceFollow`, the reciter, the audio origin.

