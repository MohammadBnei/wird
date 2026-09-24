# 4. The operations view sits behind Authentik's group, and can only see totals

Date: 2026-09-24. Status: accepted.

## Context

Reports arrive through the outbox and land in `reports`. Somebody has to read
them, and the same person wants to know whether the thing is healthy: how many
readers there are, how many sets have been prayed, how much is failing to sync.

Wird knows which ayas a person has understood, what they wrote in their notes,
and when they prayed. A dashboard over that database is surveillance of
somebody's spiritual practice unless it is built not to be, and "we won't look"
is not a design. Two questions had to be answered before any of it was written:
who is allowed in, and what is on the other side of the door.

## Decision

**Authorisation is the `platform-admins` group in Authentik, read out of the
token's claims.** Grafana reads that same membership list for `Admin` and
ArgoCD for `role:admin`; Wird's operations view becomes the third reader of one
list. There is no roles table, no per-app user administration, and no "admin
user" concept inside Wird at all — `users` stays what it is, which is readers.
An operator is somebody Authentik says is in the group, and nothing about that
is stored here.

**The login flow is the cluster's forwardAuth; the authorisation decision is
this app's.** The two patterns already in the cluster were a confidential
client and a forwardAuth route. A confidential client means an OAuth code
flow, a client secret to hold, and session cookies to get right — a few hundred
lines of the most security-sensitive code in the repo, written for one internal
page. forwardAuth is the lighter one, and it is what we take.

What we do not take from it is the *answer*. A proxy that asserts
`X-authentik-groups` is trusted network security: anything that can reach the
port is an admin. So the requirement on the deployment is that the outpost
forwards the **signed** token, and `adminweb` verifies it itself — signature
against the issuer's JWKS, audience `wird-admin` (its own, not the readers'
app), and the group read from the verified claims. The header it arrives in,
`Authorization: Bearer` or `X-Forwarded-Access-Token`, buys nothing: both go
through the same verifier, so setting one by hand gets a 401.

If the outpost cannot be made to forward a token, the fallback is the
confidential client, and that is the cost of this decision rather than a
surprise. The app's own code would barely move: the verifier stays, and what
changes is where the token comes from.

**The page can only see totals and what readers chose to send.** This is the
thing the design is accountable to, so it is structural rather than a habit:

- Every number on the page comes from `store.Health`, and every report from
  `store.Reports`. Neither takes a reader, and `reports` has no `user_id`
  column. **That is a statement about the page and about the column list, and
  neither of them is the database.** Four separate channels were found under
  that sentence, each one proved by running the attack against a real Postgres
  rather than argued:

  1. The row's id was the op id, and `op_log` holds the op id against the
     reader who sent it for the ninety days of the replay window.
  2. The report row and that `op_log` row were written in one transaction, so
     both row versions carried the same `xmin`. `xmin` is a system column and
     every role that can `SELECT` can read it, so `JOIN op_log o ON o.xmin =
     r.xmin` named three authors out of three.
  3. Physical heap order was arrival order, which an operator can walk beside
     `op_log`'s timestamps; and `created_at` was the device's clock to the
     microsecond, so the `op_log` row nearest a report in time was its
     author's.
  4. The transaction the report had been given *so that it would not share
     one* was then spent on nothing: once the table was rewritten, no live row
     carried that id. It was a gap in the transaction id sequence, sitting
     immediately above the reporter's own `op_log.xmin`. Walking the gaps named
     two reporters of three, and `op_log.xmin = (SELECT DISTINCT xmin FROM
     reports) - 1` named the third. The daily regroup, which the previous
     version of this document offered as the mitigation, **completed the
     attack**: it turned the last report's transaction into a gap like the
     others, taking the walk from two of three to three of three.

  **Four channels, each one made by the fix before it, is not four careless
  fixes — it is the wrong shape of fix.** Every one of them was a patch on an
  observable left behind by writing a report at the moment one particular
  reader was talking to the database. The op id, the shared transaction, the
  position on disk, the clock and the gap are one fact in five costumes: the
  write happened when the reader did.

  **So the write stops happening then.** A report lands in `report_inbox`, in
  the op's own transaction — nothing minted, no second transaction, nothing
  spent that the `op_log` row does not already account for, so no gap — and
  `SweepReports` moves it into `reports` on a fixed ten-minute tick. The
  sweep rewrites the whole table on every tick whether or not anything
  arrived, so the transaction id a report carries is a fact about the clock
  and about nothing else, and the `op_log` row below it is whoever happened to
  be writing at the tick rather than necessarily somebody who reported. The
  row's id is minted by the sweep, and the rows are laid down in the order of
  those ids, so neither the id nor the place on disk came from the reader's
  moment either. The day is still the device's day, and that was already
  decided.

  What holds that shut is `TestTheFourClosedChannelsFromAReportToItsAuthorStayClosed`, which
  walks a real database outwards from a real report — over the values, over
  the system columns, over the transaction ids and the clock as
  nearest-neighbours rather than as equalities, and over the order the rows
  sit in on disk — and
  `TestAReportsArrivalLeavesNoGapInTheTransactionIds`, which enumerates every
  transaction id any live row carries, walks the ids in between that nothing
  carries, and fails if one of them sits above the `op_log` row of a reader who
  reported. Each channel is then staged by hand and the walk has to find it,
  so a walk that has stopped working cannot read as a pass.

  **What is open, said exactly, because four rounds of saying otherwise is
  enough.** The claim this repository can keep is now two claims, and they are
  not the same size:

  - *The operations view cannot attribute a report.* This is structural and it
    is tested three ways: the page has no store method that takes a reader,
    `adminweb` holds no SQL of its own, and no reader's id or subject appears
    in the rendered HTML.
  - *In the database, a report can be attributed — swept or not.* This
    replaces a sentence that claimed the opposite, which a gate falsified from
    a role holding nothing but `SELECT`.

    Unswept, a row in `report_inbox` carries its author's transaction id
    openly, because it is written in its author's transaction. That is the
    price of not spending a transaction to hide in, and it lasts one tick.

    Swept, **channel 5**: a report op writes `op_log` and `report_inbox` and
    nothing else, so once the sweep empties the inbox the reporter's `op_log`
    row is the only live row in the schema carrying its transaction id. Every
    ordinary write — an understood aya, a kept note, a prayed set — shares its
    transaction id with the row it made. Being alone is the signature, and it
    is carried rather than missing, which is why the gap walk could not see it.
    Measured: 3 of 3 reporters named, 0 of 6 quiet readers. `reports.written_on`
    then binds the name to a row, outright where one reader was active that day.

    Five rounds found five channels and each fix created the next: the op id,
    the shared transaction, the position on disk, the gap left by a transaction
    spent to hide in, and now a transaction that is not shared. They are one
    fact in five costumes — *a report is written because a particular reader
    asked, and the op carrying it is a receipt for that.* Moving the write off
    the reader's moment does not move the op. A sixth patch would find a sixth
    channel, so this stops here with the claim narrowed to what is true.

    The upgrade, when the narrow claim stops being enough, is a role that
    reaches this data only through views — a view has no `xmin` — and that is a
    deployment change rather than a schema one. Note that `platform-admins` is
    the same membership list holding cluster database access, so "the operator"
    and "somebody with a SQL prompt" are not different people today.

  **And what has still not been checked**, so the next person does not read
  the above as more than it is: the database server's own statement log, which
  would hold the report body and the `op_log` insert against one session;
  `pg_locks` watched live during a write, whose object id is a hash of the
  reader's id; the WAL; commit timestamps, if the cluster is ever run with
  `track_commit_timestamp` on; and anything reachable with `pageinspect` or
  another superuser extension, which can read the dead row versions a sweep
  leaves behind until they are vacuumed. The previous version of this document
  called the unchecked layers "outside this repository", and that was false —
  channel 4 was stored in this schema and queried afterwards out of a plain
  `SELECT`. What is true is narrower: **everything checked here assumes a
  reader who has `SELECT` on these tables and nothing more.** An operator
  holding the API's own credentials has more than that. The upgrade, if the
  narrower claim ever stops being enough, is a separate database role for the
  operations view that reaches the data only through views — a view has no
  `xmin` to read — and that is a deployment change rather than a schema one.

- `adminweb` holds no SQL of its own. A test parses this package's source, and
  fails if it calls any exported store method other than `Health`, `Reports`
  and `CorpusVersion`, or if a string literal in it looks like a query. The
  method list is read out of the store's own source, so a per-reader method
  added next year is covered without anybody remembering to add it.
- A second test renders the page from a real database holding two readers and
  fails if their ids or subjects appear anywhere in the HTML.

An operator who wants to watch one named person has to add a store method and
change a test that says why not, in front of a reviewer. That is the whole
protection, and it is the one we can keep.

**Nothing is invented.** A device that did not say which corpus it had sends a
zero, and the page prints "corpus not said" rather than "corpus v0", which
would read as a build that exists. A section that could not be read says so
instead of falling through to an empty list, because "no reports yet" and "the
query failed" look identical once both are blank, and a dashboard is believed.

**Go and `html/template`, served with the vendored Nocturne stylesheet.** No
build step, no second frontend toolchain, and the page looks like Wird because
it is Wird's own design system. The obvious alternative, a Flutter web build,
is the wrong one and this project established that the hard way: `sqflite`,
`just_audio` and `wakelock_plus` have no web implementation.

## Consequences

The stylesheet is read from disk at startup (`NOCTURNE_CSS`, defaulting to
`docs/design/nocturne-styles.css`) rather than embedded, so the design system
has exactly one copy in this repo and the admin page cannot drift from it. The
binary refuses to start without it, because an unstyled wall of rows is not an
operations page.

Being in `platform-admins` is all-or-nothing: whoever can read the reports can
read every total. There is no second, narrower role, and there should not be
one until somebody names a person who needs it.

Reports are one-way. There is nothing on this page to answer with, which is
also why no report carries a reader to answer to.

A report's id being the server's own costs the one thing the op id bought past
`OpLogWindow`: a flush replayed more than ninety days later files a second
report rather than landing on the first. Inside the window `op_log` still
catches the replay before the report is written. A duplicate in a list somebody
reads is a smaller harm than a private report that names its author, and the
device that replays a ninety-day-old op is already broken.

A report is not in front of an operator until the next sweep, so a bug report
is read up to ten minutes after it was sent rather than at once. That is the
same ten minutes as the window above, because it is the same tick: shortening
one shortens the other, and the floor on both is however often the table can
stand to be rewritten. Reports arrive a handful a day and nothing else writes
the table, so the tick is cheap, and the ceiling is marked in `SweepReports`
rather than left to be discovered.

The op id and the report now commit together again, in one transaction, which
is what removes the second transaction id the gap was made of. It also removes
the duplicate the split bought: a server that dies mid-write loses both halves
and the device's retry is clean, rather than filing the report twice.

A report is kept to the day it was written and not to the minute. An operator
reads reports by day — the list is ordered by day and the page prints a day —
so nothing they were using is gone. What a bug report loses is the ability to
be lined up against a log line by the second, and the app version, platform
and screen it carries are what actually ties it to a build.
