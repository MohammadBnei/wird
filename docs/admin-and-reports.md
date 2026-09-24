# Admin dashboard and reader reports

Requested 2026-09-23, to run AFTER the app rounds. Scope written down before
building so it can be corrected.

## Two things, and they meet in the middle

1. **Readers report from inside the app** — a bug, a request, an improvement.
2. **An admin web app** where those reports are read, and where the health of
   the thing is visible.

## The line that decides the design

Wird is a devotional app. It knows which ayas a person has understood, what
they wrote in their notes, when they prayed and how often. **An admin dashboard
over that is surveillance of someone's spiritual practice unless it is built
not to be.**

So the rule, and it constrains everything below: the dashboard shows
**aggregates and what people chose to send**. Never an individual's notes, never
an individual's progress, never "who prayed when". If a query would let an
operator watch one named person's practice, it does not get written.

That is a decision, not a default, and it should survive contact with the first
time it would be convenient to break it.

**And it is a decision about two different things, which have to be said
apart.** One is the page: what an operator can ask for and see. The other is
the database the page sits on: what someone with a SQL prompt and the same
group membership can work out. The page was right from the start; the database
was not, and four channels have been found in it that no column showed — the
report stored under its op id, the report and its op_log row sharing a
transaction id, the report's clock and its place on disk sitting beside its
author's flush, and the transaction the report was given so it would not share
one, which the rewrite then left carried by no row at all: a gap in the
sequence directly above its author's.

All four were the same fact — the report was written at the moment its author
was talking to the database — so the fix is not a fifth patch. A report now
lands in `report_inbox` inside the op's own transaction and is moved into
`reports` by a sweep on a ten-minute tick that runs whether or not anybody
reported. Nothing of the reader's moment reaches the table an operator reads.

**What that leaves open, exactly.** Two things, both measured from a role
holding nothing but `SELECT`, and both still open as of 2026-09-24:

1. A report sitting in `report_inbox` carries its author's transaction id,
   openly, for up to one tick.
2. **A swept report is still attributable.** A report op writes `op_log` and
   `report_inbox` and nothing else, and the sweep empties the inbox — so the
   reporter's `op_log` row is left as the only live row in the schema carrying
   its transaction id, while every ordinary write shares its id with the row it
   made. Being alone is the signature. Measured: 3 of 3 reporters named, 0 of 6
   quiet readers. `reports.written_on` then binds the name to a row, and where
   only one reader was active that day it does so outright.

**Five rounds found five channels, and each fix created the next one.** The op
id, the shared transaction, the position on disk, the gap left by a transaction
spent to hide in, and now a transaction that is not shared. They are one fact
wearing five costumes: *a report is written because a particular reader asked,
and the op that carries it is a receipt for that.* Moving the write off the
reader's moment does not move the op.

So the honest claim is the narrow one, and it is the one this document now
makes: **an operator using the operations view cannot attribute a report.**
That is structural — no store method the page can reach takes a reader,
`adminweb` holds no SQL of its own, and no reader's id or subject appears in
the rendered HTML. **An operator with a SQL prompt on this database can.**

`platform-admins` is the same membership list that holds cluster database
access, so those are not different people today. Closing the gap between them
is a deployment change and not a schema one: a role that reaches this data only
through views, because a view has no `xmin`. That decision is the project's,
and until it is made the sentence above is the whole of what is true.

Still never checked, listed rather than waved at: the statement log, `pg_locks`
watched live, the WAL, commit timestamps if the cluster is ever run with
`track_commit_timestamp`, and anything `pageinspect` or another superuser
extension can reach, including dead row versions a sweep leaves until vacuum.

## Reports

**A report is a write like any other**, which means it goes through the outbox.
A reader who hits a bug on a plane writes it there and it flushes when a signal
returns — the same path as an understood aya. No second mechanism.

What a report carries: the text, a kind (bug / request / improvement), and the
context that makes it actionable — app version, platform, the screen they were
on. What it must NOT carry without the reader deciding: their notes, their
progress, anything from the corpus they were reading.

Server side: `report_inbox` in the existing schema, the same `client_op_id`
idempotency as every other op, and never reaching the change stream, because
reports are one-way. The sweep is what puts it in `reports`, where the
operations view reads it, on a clock that belongs to nobody — so an operator
sees a report within a tick rather than at once, which is the price of its
write not being adjacent to its author's. The day it was written is kept; the
time of day is not.

## The admin web app

**Go, server-rendered, no new stack.** `html/template` plus the Nocturne
stylesheet already vendored at `docs/design/nocturne-styles.css`. No build step,
no second frontend toolchain, and it looks like Wird because it is Wird's own
design system. A Flutter web build is the obvious alternative and is the wrong
one: `sqflite`, `flutter_appauth`, `just_audio` and `wakelock_plus` have no web
implementation, which this project already established the hard way.

**Behind Authentik**, which is live as of tonight (ADR-0050, `client_type:
public` for the app; the admin app is a separate, confidential client or a
forwardAuth route — the cluster already has both patterns, and forwardAuth is
the lighter one for an internal tool).

What it shows:
- the reports, readable and answerable
- aggregate health: how many readers, how many sets prayed, sync failures,
  parked writes IN AGGREGATE — the count, never whose
- corpus version in the field, so a bug report can be tied to a build

## Decided

**Reports are one-way.** A reader writes one and it goes; nothing comes back.
Simpler, and it sets the expectation honestly rather than implying a
correspondence nobody has committed to answering.

**The admin app lives in this repo.** It shares the schema and the design
system, so splitting it would mean two copies of both.

**Roles come from Authentik, via the group the cluster already uses.**
`platform-admins` — declared in
`infra-bootstrap/gitops/bootstrap/authentik-blueprint-groups.yaml`, read by
Grafana for `Admin` and by ArgoCD for `role:admin`. Wird's admin app becomes the
third reader of one membership list. No roles table, no per-app user
administration, nothing to keep in sync: being in the group is the whole
authorisation model, exactly as it is for the other two.

That also means there is no "admin user" concept inside Wird at all. The app's
own `users` table stays what it is — readers — and an operator is simply
somebody Authentik says is in the group.
