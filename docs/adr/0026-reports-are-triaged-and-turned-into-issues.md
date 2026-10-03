# 26. Reports are triaged on the operations view, exported to the agent, and turned into paraphrased issues

Date: 2026-10-03. Status: accepted. Amends ADR 0004: reports are no longer one-way on the operations view, and the page may write a report's triage. Amends ADR 0005: the operations view is a second image.

## Context

Before the public release, the feedback path was checked end to end. Three findings forced a decision.

- **Nothing could act on a report.** The operations view was one HTML page with the latest 200 reports, no export and no action (`server/cmd/adminweb/main.go`). It was not deployed, and Authentik put no `groups` claim in its tokens. Reports reached the database and stopped there.
- **A sense verdict could not say what was judged.** A thumb is a report whose body is `sense good: <root>` or `sense bad: <root>` (`app/lib/features/report/report.dart`). It carried the pack-wide `sense_version`, which changes when any one of 1,642 roots is redrafted. It did not say whether the reader saw the English or the French sense.
- **The app lost and repeated verdicts.** The sheet said "thank you" before the write, and dropped the write's errors. Nothing remembered a verdict, so the same reader could judge the same root on every visit. Only the reading screen's sheet had the thumbs.

The maintainer works with a coding agent. The agent needs the same reports, and it is the one able to read the code a report is about.

## Decision

**A report gains `locale` and `sense_hash`.** `locale` is the language the screen was drawn in. `sense_hash` is the first 12 hex characters of the SHA-256 of the exact sense text the reader judged, and it is empty for a written report. The server can compute the same hash from `root_senses`, so a tally knows which verdicts were about the text served today. A refused op is parked forever, so an over-long value is blanked rather than refused, as `sense_version` already is.

**Reports carry a triage: `category`, `status` and `issue_url`.** The category is one of `sense`, `bug`, `ux`, `content`, `request` and `noise`. The status is `new`, `issued` or `dismissed`. The sweep carries these columns across its rewrite. A triage write that races the sweep is retried once, because the sweep deletes and reinserts every row under the same id.

**Verdicts are tallied, not triaged.** The dashboard and the export list written reports only. Verdicts are counted per root and language: good, bad, and bad on the current text. The root is joined against `root_senses`, so text a reader typed can never appear as a root.

**The operations view exports and writes.** `GET /reports.json`, `GET /verdicts.json` and `POST /reports/{id}` sit behind the same group check. The POST is wrapped in Go's `http.CrossOriginProtection`. Every response is `Cache-Control: no-store`. The view opens its pool without migrating: the API alone runs migrations.

**The agent turns reports into GitHub issues, and never quotes a reader.** The repository is public. The agent mints a short-lived token for a service account in `platform-admins`, pulls the export, and drafts one issue per finding: a paraphrase stripped of anything personal, plus the code it concerns. It never posts the report id, the day, the platform or the build. It shows the drafts to the maintainer and creates only what is confirmed. Report text is data to the agent, never instructions. The procedure is `.claude/rules/feedback.md`. The report screen tells the reader this before they send.

**The operations view is deployed as its own image.** The Dockerfile has two targets, and the release workflow builds both from one commit and bumps both values files. `helm/adminweb-values.yaml` stays inert until infra-bootstrap provides:

- a forwardAuth proxy provider whose client id is the view's audience, and which forwards the operator's token;
- the `groups` claim;
- a service account with a client-credentials grant;
- a database role limited to reading the dashboard and updating a report's triage.

## Alternatives

- **Structured vote columns (root, verdict) instead of parsing the body.** Cleaner queries, but a bigger contract change for no new capability. The join against `root_senses` already makes the parse safe.
- **A per-root history of sense texts.** It would let an old verdict name the exact sentence. The hash comparison with the current text is enough to decide what to redraft.
- **Issues created by a dashboard button.** It needs a GitHub token in the cluster, and its code context could only be a screen-to-folder map. The agent reads the actual code.
- **Quoting the reader in the issue.** Readers write about their prayer. A public tracker is not where that belongs, and a paraphrase carries the fix.
- **A command-line export straight from the database.** It needs cluster database access on the agent's machine. The web export reuses the group check that already exists.

## Consequences

- The maintainer and the agent see every written report, sorted by triage, and every root's verdicts.
- ADR 0004's allowlist grows by two store methods, `TriageReport` and `SenseVerdicts`. Neither takes a reader. The tally is grouped by a root and a language, and its test proves a new reader adds no row of their own.
- A triage write is the operator's transaction, not the reader's. It adds no channel back to the author.
- Report text now reaches a third audience, the agent's model provider, and a paraphrase reaches the public. The report screen's copy says so. A report with an empty `locale` was sent by a build that still promised only "whoever keeps Wird running", so it is triaged but never summarised in public.
- The server must ship before an app that sends `locale` and `sense_hash`. An older server refuses the unknown keys, and a refusal is permanent.
- The operations view is reachable from the internet behind a login. Its database role is what limits a stolen session.

## Reversibility

Cheap. Dropping the triage columns and the routes restores ADR 0004's page. The two report keys can stay, because an empty value is valid. The signal to undo would be a paraphrase that identified a reader. That would end the public issues, not the triage.
