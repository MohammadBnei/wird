# 32. Account deletion removes Wird's data and keeps the shared sign-in

Date: 2026-10-04. Status: accepted. Amends ADR 0028.

## Context

Both stores require in-app account deletion (ADR 0028). Wird's deletion is `DELETE /v1/me`: it removes the reader and every row it owns, records a hash of the subject so a stale token cannot recreate it, and the app empties the phone ([store.go](../../server/internal/store/store.go), [auth.md](../architecture/api/auth.md)).

The sign-in itself is a bnei.dev account in Authentik, an email and password. Other bnei.dev services share it. Wird's server only validates tokens and never holds Authentik credentials (`.claude/rules/server.md`). Apple guideline 5.1.1(v) asks that deleting an account deletes the account, not only its data, so a strict reviewer may reject a deletion that leaves the sign-in in place.

## Decision

- Deleting from the app removes the Wird account and all of its data, and empties the phone. The shared bnei.dev sign-in stays.
- The privacy page, the in-app flow and the review note say exactly that, and never call the kept sign-in "deleted". The privacy page tells the reader how to have the sign-in removed by email.
- The review demo account survives each deletion, so one account serves every review.

## Alternatives

- **The server deletes the Authentik user on `DELETE /v1/me`.** Fully meets 5.1.1(v). But the API would need an Authentik admin token, which breaks the rule that it only validates tokens, and deleting a Wird account would also cut the reader off from other bnei.dev services without asking.
- **Deletion by email only.** Not accepted by either store.

## Consequences

- A review may come back rejected under 5.1.1(v). The answer then is the first alternative, for the Wird-only case: delete the Authentik user when it has no other application, through a narrowly scoped service token.
- The demo account needs no re-creation between reviews.
- The privacy page and the review note must stay word for word consistent on what is deleted.

## Reversibility

Cheap to reverse: one server change plus a scoped Authentik token, and new wording. The signal is a rejection that cites 5.1.1(v).
