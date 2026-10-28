# Sync endpoints

> The server side of `POST /v1/sync` and `GET /v1/changes`: where the outbox lands, and where a second device catches up. Level L2 · Parent [API](../api.md) · Children none

## Black box

These two endpoints are the whole of sync. The app's outbox sends every write through `POST /v1/sync`, online or not, and gets one verdict back per write. A device then asks `GET /v1/changes` for everything that changed since its cursor, so a phone and a tablet end up holding the same state. Both need a bearer token. The client half is [Sync in the app](../app/sync.md).

| In | Out | Depends on |
|---|---|---|
| A batch of ops, each with a device-minted `client_op_id`, a kind and a body | One result per op: `applied`, `duplicate`, `refused` or `failed` | A signed-in reader (see [Auth](auth.md)) |
| A cursor from the last pull, or none | Up to 500 changed rows, the next cursor, and whether more are waiting | Postgres |

```mermaid
sequenceDiagram
  participant Out as Outbox on the device
  participant Sync as POST /v1/sync
  participant Changes as GET /v1/changes

  Out->>Sync: ops, each with client_op_id
  Sync-->>Out: one result per op
  Note over Out: applied or duplicate: drop from outbox<br/>refused: park it at once<br/>failed: retry later, park after too many tries
  Out->>Sync: same op again after a timeout
  Sync-->>Out: duplicate, nothing counted twice
  loop until more is false
    Out->>Changes: since = last cursor
    Changes-->>Out: changes, next cursor, more
  end
```

Three promises hold from outside:

- **Sending an op twice is safe.** The second send answers `duplicate` and changes nothing.
- **One bad op never blocks the rest.** Each op gets its own verdict. The whole batch fails only when it is unreadable, has more than 500 ops, is over one megabyte, or the database cannot be reached at all.
- **A pull never misses a write.** The cursor follows the order writes land on the server, not the device's clock. A write made offline on Monday and sent on Friday still reaches a tablet that last pulled on Wednesday.

## White box

```mermaid
flowchart TB
  req["POST /v1/sync"] --> read{"body readable,<br/>at most 500 ops,<br/>at most 1 MB?"}
  read -->|no| bad["400, whole batch"]
  read -->|yes| each["for each op, in order"]
  each --> tx["begin transaction"]
  tx --> lock["lock this reader"]
  lock --> log{"insert client_op_id<br/>into op_log"}
  log -->|"already there"| dup["duplicate"]
  log -->|new| kind["apply by kind"]
  kind -->|ok| commit{"commit"}
  commit -->|ok| ok["applied"]
  kind -->|error| cls{"whose fault?"}
  commit -->|error| cls
  cls -->|"device's"| ref["refused"]
  cls -->|"server's"| fail["failed"]
  ref & fail --> count["add one to sync_outcomes"]
```

### 1. The handler reads the batch and hands it over

`sync` caps the body at one megabyte and the batch at 500 ops, then passes the ops to the store. Only an unreadable or oversized batch is refused whole with a 400. If the store cannot even open a transaction, the whole batch answers 500. [sync.go:30-48](../../../server/internal/api/sync.go#L30-L48)

```go
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxSyncBody)).Decode(&batch); err != nil {
		httpx.Error(w, errs.InvalidArgument, keys.BadBatch, "the batch is not readable")
		return
	}
	if len(batch.Ops) > maxOpsPerBatch {
		httpx.Error(w, errs.InvalidArgument, keys.BatchTooBig, "too many ops in one batch")
		return
	}
	results, err := h.store.Apply(r.Context(), auth.User(r.Context()).ID, batch.Ops)
	if err != nil {
		h.fail(w, "sync", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"results": results})
```

An op is three fields: `client_op_id`, `kind` and a raw `body`. [store/sync.go:25-29](../../../server/internal/store/sync.go#L25-L29)

### 2. Each op gets its own transaction

`Apply` walks the ops in order and lands each one alone. [store/sync.go:71-81](../../../server/internal/store/sync.go#L71-L81) Inside the transaction, three things happen in a fixed order. [store/sync.go:120-135](../../../server/internal/store/sync.go#L120-L135)

```go
func applyInTx(ctx context.Context, tx pgx.Tx, userID string, op Op) OpResult {
	if err := lockReader(ctx, tx, userID); err != nil {
		return classify(op, err)
	}
	first, err := recordOp(ctx, tx, userID, op.ClientOpID)
	if err != nil {
		return classify(op, err)
	}
	if !first {
		return OpResult{ClientOpID: op.ClientOpID, Status: OpDuplicate}
	}
	if err := applyKind(ctx, tx, userID, op); err != nil {
		return classify(op, err)
	}
	return OpResult{ClientOpID: op.ClientOpID, Status: OpApplied}
```

The transaction only commits when the op was `applied`. So the `op_log` row and the write it stands for commit together or not at all. If they could split, a retry would look like a replay and the write would be lost. [store/sync.go:100-115](../../../server/internal/store/sync.go#L100-L115)

### 3. Idempotence: the op log

`op_log` has the key `(user_id, client_op_id)`. Inserting an id that is already there does nothing, and that is how a replay is spotted. [00001_user_state.sql:71-76](../../../server/migrations/00001_user_state.sql#L71-L76), [store.go:337-345](../../../server/internal/store/store.go#L398-L406)

```go
	tag, err := q.Exec(ctx, `
		INSERT INTO op_log (user_id, client_op_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING`, userID, clientOpID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
```

The API prunes op log rows older than 90 days ([store.go:348](../../../server/internal/store/store.go#L409)). A replay older than that is still safe for most kinds, because the writes themselves are upserts or skip rows already there. A report is the exception: replayed that late, it would land twice. [store/sync.go:584-588](../../../server/internal/store/sync.go#L584-L588) A prayer with no id of its own takes the op id as its row id, so even that replay lands on the same row. [store/sync.go:492-497](../../../server/internal/store/sync.go#L492-L497)

### 4. The reader lock keeps the cursor honest

Before anything else, the transaction takes an advisory lock on the reader. A sequence number is handed out when a row is written, not when it commits. Without the lock, two writes in flight could commit in the opposite order to their numbers, and a device whose cursor had passed the lower number would never see that row. With it, one reader's writes land one at a time. [store/sync.go:137-157](../../../server/internal/store/sync.go#L137-L157)

The same lock makes the server-assigned set `ordinal` safe: `MAX(ordinal) + 1` cannot race. [store/sync.go:398-427](../../../server/internal/store/sync.go#L398-L427)

### 5. Apply by kind

`applyKind` dispatches on the op's kind. An unknown kind is refused. [store/sync.go:213-234](../../../server/internal/store/sync.go#L213-L234)

| Kind | What it writes | Rule |
|---|---|---|
| `ayah_understood` | One row per aya in `ayah_understood` | Each aya id must fold into a sūra from 1 to 114; already-understood ayas are skipped. [L230](../../../server/internal/store/sync.go#L267) |
| `kept_upsert` | A `kept_items` row | Last write wins on `updated_at`; another reader's item never moves. [L277](../../../server/internal/store/sync.go#L314) |
| `kept_delete` | Sets `deleted_at` on a `kept_items` row | A tombstone, never a delete. [L301](../../../server/internal/store/sync.go#L338) |
| `set_prayed` | The set, if the body carries its range, and the prayer | With a range, the set id is recomputed and must match. Either way the set must exist. [L427](../../../server/internal/store/sync.go#L464) |
| `set_recorded` | A set | Old shape, kept so old phones can drain their queue. [L398](../../../server/internal/store/sync.go#L435) |
| `prefs_set` | The reader's `user_prefs` | Reading order must be `mushaf` or `nuzul`; last write wins. [L604](../../../server/internal/store/sync.go#L641) |
| `position_moved` | The reader's `reading_positions` row for that sūra | The word must belong to the sūra; the time must be set and no more than five minutes ahead of the server; last write wins. [L632](../../../server/internal/store/sync.go#L669) |
| `report_written` | A row in `report_inbox`, with no reader attached | Swept into `reports` later, on a clock. An over-long `sense_version` or `sense_hash`, or a `locale` other than `en` or `fr`, is blanked, not refused, so the words survive. [L498](../../../server/internal/store/sync.go#L535) |

Every body is decoded strictly. One unknown field refuses the op. [store/sync.go:257-265](../../../server/internal/store/sync.go#L257-L265) So a server has to ship before an app that sends a new key: an older server refuses it, and a refusal is permanent. `locale` and `sense_hash` on `report_written` were added that way ([ADR 0026](../../adr/0026-reports-are-triaged-and-turned-into-issues.md#consequences)).

```go
func decode(body json.RawMessage, into any) error {
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return refuse("%s", err)
	}
	return nil
}
```

This is why the app must never send a new field before the server that accepts it is live.

### 6. Refused or failed

`classify` splits errors into two answers. `refused` means the device sent something that will never land: a bad body, a bad value, a missing set. Postgres data errors (class 22) and constraint errors (class 23) count as refused too. Anything else is `failed`, which the device should retry. [store/sync.go:162-170](../../../server/internal/store/sync.go#L162-L170)

```mermaid
stateDiagram-v2
  [*] --> applied: new id, write ok
  [*] --> duplicate: id already in op_log
  [*] --> refused: device's fault
  [*] --> failed: server's fault
  applied --> [*]: device drops it
  duplicate --> [*]: device drops it
  refused --> [*]: device parks it, never resends
  failed --> [*]: device sends it again later
```

Each refused or failed result carries a `reason` and a `key`. The reason is words for a person, kept as a string because installed apps parse it ([outbox.dart:62](../../../app/lib/data/outbox.dart#L62)). It never names a table or a statement, and a body the decoder refuses gets fixed words rather than the decoder's text, which names Go types. [store/sync.go:194-211](../../../server/internal/store/sync.go#L194-L211) The key is what a client branches on: `op.unknown_kind`, `op.bad_body`, `op.bad_value`, `op.not_found` or `op.conflict` for a refusal, and `op.retry` for a failure. Each `refuse` call names its key, and a Postgres error gets its key from its class, as the reason does. [store/sync.go:172-190](../../../server/internal/store/sync.go#L172-L190) Refused and failed ops are counted per day, kind and verdict in `sync_outcomes`, with no reader attached, so the operations view can see that syncs fail without seeing whose. [store/sync.go:248-255](../../../server/internal/store/sync.go#L248-L255)

### 7. The pull: `GET /v1/changes`

```mermaid
flowchart LR
  c["since cursor"] --> p{"empty, or seq:N?"}
  p -->|neither| e["400: not a cursor<br/>this server issued"]
  p -->|"empty = 0"| q
  p -->|"seq:N"| q["rows from six tables<br/>with seq above N,<br/>ordered by seq, first 500"]
  q --> r["changes + cursor seq:last<br/>+ more if the page is full"]
```

The six tables the pull reads each carry a `seq` column fed by one sequence, `change_seq`. Each insert takes the next number, and each update of a kept item, of preferences or of a reading position takes a fresh one. [00003_change_order.sql:11-17](../../../server/migrations/00003_change_order.sql#L11-L17), [store/sync.go:329](../../../server/internal/store/sync.go#L329), [store/sync.go:350](../../../server/internal/store/sync.go#L350), [store/sync.go:657](../../../server/internal/store/sync.go#L657) `root_known` has no `seq` and is not in the stream.

The query unions `ayah_understood`, `kept_items`, `sets`, `set_prayers`, `user_prefs` and `reading_positions`, orders by `seq`, and stops at 500 rows. A kept item with `deleted_at` set is sent like any other row: that row is the tombstone. [store/sync.go:725-758](../../../server/internal/store/sync.go#L725-L758)

The cursor is the text `seq:` followed by the last number sent. A cursor without that prefix is refused with a 400 rather than read as some place in the stream. [store/sync.go:805-824](../../../server/internal/store/sync.go#L805-L824)

```go
func parseCursor(cursor string) (int64, error) {
	if cursor == "" {
		return 0, nil
	}
	rest, found := strings.CutPrefix(cursor, cursorPrefix)
	if !found {
		return 0, ErrBadCursor
	}
	seq, err := strconv.ParseInt(rest, 10, 64)
	if err != nil || seq < 0 {
		return 0, ErrBadCursor
	}
	return seq, nil
}
```

When a page comes back empty, the cursor the device sent is returned unchanged. `more` is true only when the page is full. [store/sync.go:791-794](../../../server/internal/store/sync.go#L791-L794) The endpoint writes nothing.

### 8. One file both sides answer to

Four things cross the device and server boundary with no compiler to check them: the op body field names, the four result words, the six change kinds with their row keys, and the two reading-order words. They are written once, in [0002-sync-contract-vectors.json](../../adr/0002-sync-contract-vectors.json). The Go suite lands every op body against a real Postgres and requires `applied`, and checks the stream emits exactly those kinds and keys. [sync_contract_vectors_test.go:79](../../../server/internal/store/sync_contract_vectors_test.go#L79), [sync_contract_vectors_test.go:144](../../../server/internal/store/sync_contract_vectors_test.go#L144) The Dart suite reads the same file. [sync_contract_vectors_test.dart](../../../app/test/data/sync_contract_vectors_test.dart)

```mermaid
flowchart LR
  v[("0002-sync-contract-vectors.json")]
  go["Go suite<br/>real Postgres"]
  dart["Dart suite<br/>real write and pull path"]
  v --> go
  v --> dart
```

A change on one side reddens that side's suite. Following it into the file reddens the other. Change the file and both suites in one commit.

## Why it is this way

- [ADR 0001](../../adr/0001-stack.md) — the server is the source of truth for user state; the app keeps an outbox so prayer never waits on a socket.
- [ADR 0002](../../adr/0002-set-identity.md) — set ids are derived, a prayer is one op, and the contract vectors exist because each side's tests only agreed with themselves.
- [ADR 0004](../../adr/0004-the-operations-view-behind-authentiks-group.md) — why a report reaches an inbox with no reader, and why outcomes are counted only in totals.

## Go deeper

- [Sync in the app](../app/sync.md) — the outbox, the flush, and what the device does with each verdict.
- [API](../api.md) — the rest of the service these endpoints live in.
- [Auth](auth.md) — how the reader behind the bearer token is found.
- Tour: [A prayer, from tap to Postgres](../../tours/prayer-to-postgres.md).
