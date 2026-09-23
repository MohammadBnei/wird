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
  column to join on — a report is what somebody chose to send, and an operator
  reading it cannot turn it back into a person.
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
