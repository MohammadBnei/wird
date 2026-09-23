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
every implementation recomputes it rather than transcribing it. `store.SetID`
is the reference implementation; `setIdFor` in `app/lib/data/sets.dart` is the
device's.

The key is exactly `"<reading_order>:<start_ayah_id>:<end_ayah_id>"` — no
padding, no separator but the colon, the ayah id being `surah * 1000 + number`
and the reading order the bare words `mushaf` and `nuzul`.

### The vectors

These rows are the contract, and they are checked in at
`docs/adr/0002-set-identity-vectors.json` so both suites read the same file:
`server/internal/store/set_id_vectors_test.go` asserts `store.SetID`
reproduces them and `app/test/data/set_id_vectors_test.dart` asserts `setIdFor`
does. Neither computes its own expectation, which is what lets either one of
them fail. A third implementation checks itself here.

| reading_order | start | end | set_id |
| --- | --- | --- | --- |
| mushaf | 1001 | 1007 | 6cb8c394-ae9a-5092-a2ea-8f88749613c7 |
| nuzul | 1001 | 1007 | 6f4fbaaa-7a32-5d96-a804-0e8077875aef |
| mushaf | 2255 | 2255 | 972107a6-23d6-56cd-8468-83383277fe3c |
| nuzul | 96001 | 96001 | 65ae58b8-1656-5337-bfa4-b6bad811b853 |
| nuzul | 96001 | 96005 | cca760fb-a771-543c-918f-d98ea401b2a0 |
| mushaf | 113005 | 114001 | ea3616ae-09c2-59cf-a243-5e71d167cf1b |
| nuzul | 112004 | 113003 | de79bf3f-198d-5942-81ff-5665f8dd6005 |

al-Fātiḥa is first because it is the range two readers are likeliest to have
both prayed; the single aya, the sura-crossing range and both orders are there
because each is a place a derivation can differ without the other rows moving.

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

### What else crosses this boundary unchecked

The set id shipped wrong because each half had a test that agreed with itself:
the server built its fixtures with `store.SetID` and the device asserted
against `setIdFor`, so neither could fail when the two disagreed. The vectors
above close that for the set id. These are the other places the device and the
server hold the same contract and each verify it alone — written down, not
fixed:

* **The `set_prayed` body's field names.** The decoder is
  `DisallowUnknownFields`, so one renamed or extra key is a refusal, and a
  refusal is permanent — the same loss the set id caused. The device lists the
  names in `app/test/data/set_prayers_test.dart`; the server lists them in its
  own structs and fixtures. Nothing compares the two lists. Same for
  `ayah_understood`, `kept_upsert`, `kept_delete` and `prefs_set`.
* **The op-result vocabulary.** `applied`, `duplicate`, `refused`, `failed`.
  The device reads `refused` as permanent and everything else as transient;
  `app/test/data/sync_test.dart` gets those strings from a fake server the
  device itself writes. Rename one on the server and the device retries a write
  that can never land, or parks one that could.
* **The change-stream `kind` values.** The server emits `ayah_understood`,
  `kept_items`, `sets`, `set_prayers`, `user_prefs`; `sync.dart`'s `_apply`
  switches on the first, second and fifth and its default arm is `=> 0`. A
  renamed kind is not an error on either side — the device simply stops
  applying that table and says nothing.
* **The reading-order words.** `mushaf` and `nuzul` are an enum on the device
  and an unvalidated string on the server. The vectors above now pin their
  spelling as a side effect, which is the only thing that does.

The `sets` and `set_prayers` changes are dropped on purpose (`sync.dart`
says there is nothing local to write them to) — but the device now has both
tables, so a second device counts only the prayers it made itself and "the
fourth prayer on this set" differs per device.

Sets recorded before this decision keep their minted ids. They are a different
set from the derived one covering the same range, which shows as one extra row
in that reader's set count and nowhere else.
