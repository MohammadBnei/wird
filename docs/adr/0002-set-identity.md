# 2. A set's identity is derived, and one op records a prayer

Date: 2026-09-23. Status: accepted.

## Context

A set was identified by a uuid the device minted and numbered by an `ordinal`
the device also chose, and a prayer arrived as a second op naming the first.
Both halves broke under the things readers actually do.

`sets` carried `UNIQUE (user_id, ordinal)`. A device cannot know what number
its next set should have: it collides on a reinstall, on a second device, and
on the second set of a fresh install that guessed. The collision is SQLSTATE
23505, which the sync layer classifies as refused, which dead-letters the op
permanently — and because the prayer op refused with "no set", a refused set
killed the prayer with it.

The two ops were also unordered relative to each other. The device's outbox
orders by `(created_at, client_op_id)`, and both are enqueued in one
transaction at one instant, so the tiebreak is a random uuid. Which arrived
first was a coin flip.

## Decision

**A set's id is a pure function of the set.**

```
set_id = uuidv5(namespace, "<reading_order>:<start_ayah_id>:<end_ayah_id>")
namespace = 302f8902-5d26-53eb-bfc6-b45ac9fff0c5
```

The namespace is itself `uuidv5(NameSpaceURL, "https://wird.bnei.dev/set")`, so
it can be recomputed rather than trusted. Every device must use this literal;
`store.SetID` is the reference implementation.

A reinstall recomputes the same id. Two devices agree without coordinating.
`set_prayers WHERE set_id = ?` makes "the fourth prayer on this set"
countable. Nothing about the reader's *position* is stored, so the reading
order stays switchable.

**`ordinal` is assigned by the server**, `COALESCE(MAX(ordinal), 0) + 1` per
reader in the same transaction. It is safe as a read-then-write because that
transaction already holds the reader's advisory lock.

**One op, not two.** `set_prayed` carries
`{set_id, start_ayah_id, end_ayah_id, reading_order, prayed_at}`. The server
upserts the set and records the prayer together, idempotent on `client_op_id`.

**The id is validated, not trusted.** The server recomputes it from the range
and order in the body and refuses a mismatch. A device that derives ids
differently is a bug; unchecked it would surface months later as two sets for
one range and two wrong counts.

**Identity is per reader.** Because the id is derived, every reader who prays
al-Fātiḥa derives the same uuid, so `sets` is keyed `(user_id, id)` and
`set_prayers` references that pair.

## Consequences

Old clients keep working. `set_recorded` is still accepted, still creates the
set, and its `ordinal` field is read and ignored rather than dropped from the
struct — the decoder rejects unknown fields, so dropping it would refuse the
whole op and dead-letter exactly the writes this compatibility exists to save.
Its ids are minted rather than derived, so they are not checked against the
range; only `set_prayed` bodies that carry a range are. A `set_prayed` without
a range is the old shape and still requires its set to be there already.

Sets recorded before this decision keep their minted ids. They are a different
set from the derived one covering the same range, which shows as one extra row
in that reader's set count and nowhere else.
