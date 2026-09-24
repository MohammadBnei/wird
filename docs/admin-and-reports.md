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
was not, and three channels have been found in it that no column showed — the
report stored under its op id, the report and its op_log row sharing a
transaction id, and the report's clock sitting beside its author's flush. All
three are closed and ADR-0004 says how, and what is still unchecked. Anything
written here or anywhere else about reports not naming their author is about
one layer or the other; say which.

## Reports

**A report is a write like any other**, which means it goes through the outbox.
A reader who hits a bug on a plane writes it there and it flushes when a signal
returns — the same path as an understood aya. No second mechanism.

What a report carries: the text, a kind (bug / request / improvement), and the
context that makes it actionable — app version, platform, the screen they were
on. What it must NOT carry without the reader deciding: their notes, their
progress, anything from the corpus they were reading.

Server side: `reports` in the existing schema, the same `client_op_id`
idempotency as every other op, and never reaching the change stream, because
reports are one-way. The write is the one op whose effect does not commit in
the op's own transaction: two rows written together carry one transaction id,
and that id is readable. The day it was written is kept; the time of day is
not.

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
