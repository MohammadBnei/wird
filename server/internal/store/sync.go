package store

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// An Op is one write a device made, carrying the id it minted for it. The id
// is what makes a replay a replay: the same op sent twice is the same write,
// whether the first send timed out, the phone reconnected twice, or the reader
// pressed the button again.
type Op struct {
	ClientOpID string          `json:"client_op_id"`
	Kind       string          `json:"kind"`
	Body       json.RawMessage `json:"body"`
}

// The four things that can become of an op. They are per-op rather than
// per-batch on purpose: one refused write must not hold the other nineteen
// behind it on every reconnect until the reader loses them.
const (
	OpApplied   = "applied"
	OpDuplicate = "duplicate"
	OpRefused   = "refused"
	OpFailed    = "failed"
)

type OpResult struct {
	ClientOpID string `json:"client_op_id"`
	Status     string `json:"status"`
	Reason     string `json:"reason,omitempty"`
}

// errRefused marks a write that will never succeed however often it is sent.
// Anything else is this server having a bad minute, and is worth retrying.
var errRefused = errors.New("refused")

func refuse(format string, a ...any) error {
	return fmt.Errorf("%w: %s", errRefused, fmt.Sprintf(format, a...))
}

// Apply lands a batch one op at a time, each in its own transaction, and
// answers for each of them separately.
func (s *Store) Apply(ctx context.Context, userID string, ops []Op) ([]OpResult, error) {
	results := make([]OpResult, 0, len(ops))
	for _, op := range ops {
		result, err := s.applyOne(ctx, userID, op)
		if err != nil {
			return nil, err
		}
		results = append(results, result)
	}
	return results, nil
}

// applyOne writes the op id and the op's effect in one transaction. They
// commit together or not at all: an op id recorded for a write that rolled
// back would make the retry look like a replay and lose the write for good.
func (s *Store) applyOne(ctx context.Context, userID string, op Op) (OpResult, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return OpResult{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	first, err := recordOp(ctx, tx, userID, op.ClientOpID)
	if err != nil {
		return classify(op, err), nil
	}
	if !first {
		return OpResult{ClientOpID: op.ClientOpID, Status: OpDuplicate}, nil
	}
	if err := applyKind(ctx, tx, userID, op); err != nil {
		return classify(op, err), nil
	}
	if err := tx.Commit(ctx); err != nil {
		return classify(op, err), nil
	}
	return OpResult{ClientOpID: op.ClientOpID, Status: OpApplied}, nil
}

// classify separates the ops worth sending again from the ones that never
// will be. A malformed body, an id that is not a uuid and a prayer against a
// set that is not there are all the device's to fix; everything else is ours.
func classify(op Op, err error) OpResult {
	var pg *pgconn.PgError
	refused := errors.Is(err, errRefused) ||
		(errors.As(err, &pg) && (strings.HasPrefix(pg.Code, "22") || strings.HasPrefix(pg.Code, "23")))
	if refused {
		return OpResult{ClientOpID: op.ClientOpID, Status: OpRefused, Reason: reason(err)}
	}
	return OpResult{ClientOpID: op.ClientOpID, Status: OpFailed, Reason: "not applied, try again"}
}

// reason says what the device did wrong without saying which statement or
// which table said so.
func reason(err error) string {
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		switch {
		case strings.HasPrefix(pg.Code, "22"):
			return "the op body is not shaped like this kind"
		case pg.Code == "23503":
			return "it refers to something that is not here"
		default:
			return "it does not fit what is already recorded"
		}
	}
	if errors.Is(err, errRefused) {
		_, msg, _ := strings.Cut(err.Error(), ": ")
		return msg
	}
	return "refused"
}

func applyKind(ctx context.Context, tx pgx.Tx, userID string, op Op) error {
	switch op.Kind {
	case "ayah_understood":
		return applyAyahUnderstood(ctx, tx, userID, op.Body)
	case "kept_upsert":
		return applyKeptUpsert(ctx, tx, userID, op.Body)
	case "kept_delete":
		return applyKeptDelete(ctx, tx, userID, op.Body)
	case "set_recorded":
		return applySetRecorded(ctx, tx, userID, op.Body)
	case "set_prayed":
		return applySetPrayed(ctx, tx, userID, op.Body)
	case "prefs_set":
		return applyPrefsSet(ctx, tx, userID, op.Body)
	default:
		return refuse("unknown kind %q", op.Kind)
	}
}

func decode(body json.RawMessage, into any) error {
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return refuse("%s", err)
	}
	return nil
}

func applyAyahUnderstood(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b struct {
		AyahIDs      []int     `json:"ayah_ids"`
		UnderstoodAt time.Time `json:"understood_at"`
	}
	if err := decode(body, &b); err != nil {
		return err
	}
	if len(b.AyahIDs) == 0 {
		return refuse("no ayas to mark")
	}
	// A device that queued this op before it carried a time would otherwise
	// record the reader's understanding in year one. The flush's own time is
	// wrong by however long the phone was offline, but it is inside the life
	// of the account.
	if b.UnderstoodAt.IsZero() {
		b.UnderstoodAt = time.Now().UTC()
	}
	// The ids are the corpus's own natural keys. An id outside them would
	// count an aya that does not exist towards the one number the app exists
	// to show, so it is refused rather than stored.
	for _, id := range b.AyahIDs {
		if id/1000 < 1 || id/1000 > 114 || id%1000 < 1 {
			return refuse("%d is not an aya", id)
		}
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO ayah_understood (id, user_id, ayah_id, understood_at)
		SELECT gen_random_uuid(), $1, unnest($2::int[]), $3
		ON CONFLICT (user_id, ayah_id) DO NOTHING`, userID, b.AyahIDs, b.UnderstoodAt)
	return err
}

type keptBody struct {
	ID          string    `json:"id"`
	Kind        string    `json:"kind"`
	AyahID      *int      `json:"ayah_id"`
	RootLetters *string   `json:"root_letters"`
	Body        string    `json:"body"`
	Tags        []string  `json:"tags"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// The conflict clause is last-write-wins on updated_at, and the user_id in it
// is what stops a device that guessed another reader's item id from editing
// it: the row simply does not move.
func applyKeptUpsert(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b keptBody
	if err := decode(body, &b); err != nil {
		return err
	}
	if b.Tags == nil {
		b.Tags = []string{}
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO kept_items (id, user_id, kind, ayah_id, root_letters, body, tags, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (id) DO UPDATE
		   SET kind = EXCLUDED.kind, ayah_id = EXCLUDED.ayah_id,
		       root_letters = EXCLUDED.root_letters, body = EXCLUDED.body,
		       tags = EXCLUDED.tags, updated_at = EXCLUDED.updated_at
		 WHERE kept_items.user_id = EXCLUDED.user_id
		   AND kept_items.updated_at < EXCLUDED.updated_at`,
		b.ID, userID, b.Kind, b.AyahID, b.RootLetters, b.Body, b.Tags, b.CreatedAt, b.UpdatedAt)
	return err
}

// A tombstone, never a DELETE. A row removed here is a note the other device
// hands straight back on its next pull.
func applyKeptDelete(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b struct {
		ID        string    `json:"id"`
		DeletedAt time.Time `json:"deleted_at"`
	}
	if err := decode(body, &b); err != nil {
		return err
	}
	tag, err := tx.Exec(ctx, `
		UPDATE kept_items
		   SET deleted_at = COALESCE(deleted_at, $3),
		       updated_at = GREATEST(updated_at, $3)
		 WHERE id = $2 AND user_id = $1`, userID, b.ID, b.DeletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return refuse("no kept item %s", b.ID)
	}
	return nil
}

func applySetRecorded(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b struct {
		ID           string    `json:"id"`
		Ordinal      int       `json:"ordinal"`
		StartAyahID  int       `json:"start_ayah_id"`
		EndAyahID    int       `json:"end_ayah_id"`
		ReadingOrder string    `json:"reading_order"`
		CreatedAt    time.Time `json:"created_at"`
	}
	if err := decode(body, &b); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (id) DO NOTHING`,
		b.ID, userID, b.Ordinal, b.StartAyahID, b.EndAyahID, b.ReadingOrder, b.CreatedAt)
	return err
}

// The prayer. A set deleted server-side makes this the poison op the plan
// names: it is refused on its own and the rest of the batch still lands.
func applySetPrayed(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b struct {
		ID         string    `json:"id"`
		SetID      string    `json:"set_id"`
		PrayerName string    `json:"prayer_name"`
		PrayedAt   time.Time `json:"prayed_at"`
	}
	if err := decode(body, &b); err != nil {
		return err
	}
	var belongs bool
	if err := tx.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM sets WHERE id = $1 AND user_id = $2)`,
		b.SetID, userID).Scan(&belongs); err != nil {
		return err
	}
	if !belongs {
		return refuse("no set %s", b.SetID)
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO set_prayers (id, set_id, user_id, prayer_name, prayed_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO NOTHING`,
		b.ID, b.SetID, userID, b.PrayerName, b.PrayedAt)
	return err
}

func applyPrefsSet(ctx context.Context, tx pgx.Tx, userID string, body json.RawMessage) error {
	var b struct {
		ReadingOrder string    `json:"reading_order"`
		UpdatedAt    time.Time `json:"updated_at"`
	}
	if err := decode(body, &b); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO user_prefs (user_id, reading_order, updated_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE
		   SET reading_order = EXCLUDED.reading_order, updated_at = EXCLUDED.updated_at
		 WHERE user_prefs.updated_at < EXCLUDED.updated_at`,
		userID, b.ReadingOrder, b.UpdatedAt)
	return err
}

// A Change is one row as the other device should now hold it. A kept item
// with deleted_at set is the tombstone: it is the row, not its absence, that
// stops the second device handing a deleted note back.
type Change struct {
	Kind string          `json:"kind"`
	ID   string          `json:"id"`
	At   time.Time       `json:"at"`
	Row  json.RawMessage `json:"row"`
}

type Changes struct {
	Changes []Change `json:"changes"`
	Cursor  string   `json:"cursor"`
	More    bool     `json:"more"`
}

// ChangePage is how many rows one pull carries. A reader with years of
// progress restores in pages rather than in one answer the phone must hold
// whole.
const ChangePage = 500

const changesSQL = `
WITH changed AS (
	SELECT 'ayah_understood' AS kind, id, understood_at AS at,
	       jsonb_build_object('ayah_id', ayah_id, 'understood_at', understood_at) AS row
	  FROM ayah_understood WHERE user_id = $1
	UNION ALL
	SELECT 'kept_items', id, updated_at,
	       jsonb_build_object('id', id, 'kind', kind, 'ayah_id', ayah_id,
	                          'root_letters', root_letters, 'body', body,
	                          'tags', to_jsonb(tags), 'created_at', created_at,
	                          'updated_at', updated_at, 'deleted_at', deleted_at)
	  FROM kept_items WHERE user_id = $1
	UNION ALL
	SELECT 'sets', id, created_at,
	       jsonb_build_object('id', id, 'ordinal', ordinal, 'start_ayah_id', start_ayah_id,
	                          'end_ayah_id', end_ayah_id, 'reading_order', reading_order,
	                          'created_at', created_at)
	  FROM sets WHERE user_id = $1
	UNION ALL
	SELECT 'set_prayers', id, prayed_at,
	       jsonb_build_object('id', id, 'set_id', set_id, 'prayer_name', prayer_name,
	                          'prayed_at', prayed_at)
	  FROM set_prayers WHERE user_id = $1
	UNION ALL
	SELECT 'user_prefs', user_id, updated_at,
	       jsonb_build_object('reading_order', reading_order, 'updated_at', updated_at)
	  FROM user_prefs WHERE user_id = $1
)
SELECT kind, id, at, row FROM changed
 WHERE (at, id) > ($2, $3::uuid)
 ORDER BY at, id
 LIMIT $4`

// Changes is the pull half. The cursor is the (timestamp, id) of the last row
// handed over, so two rows written in the same microsecond cannot hide behind
// each other and none is handed over twice.
//
// ponytail: a timestamp read at write time, not a commit-ordered sequence. A
// transaction that committed late enough to fall behind a cursor already
// issued would be missed; every write here is a single statement, so that
// window is microseconds wide. If it ever matters, the upgrade is a change_log
// whose number is assigned at commit.
func (s *Store) Changes(ctx context.Context, userID, cursor string) (Changes, error) {
	at, id, err := parseCursor(cursor)
	if err != nil {
		return Changes{}, err
	}
	out := Changes{Changes: []Change{}, Cursor: cursor}
	rows, err := s.pool.Query(ctx, changesSQL, userID, at, id, ChangePage)
	if err != nil {
		return out, err
	}
	defer rows.Close()

	for rows.Next() {
		var c Change
		if err := rows.Scan(&c.Kind, &c.ID, &c.At, &c.Row); err != nil {
			return out, err
		}
		out.Changes = append(out.Changes, c)
	}
	if err := rows.Err(); err != nil {
		return out, err
	}
	if n := len(out.Changes); n > 0 {
		last := out.Changes[n-1]
		out.Cursor = last.At.UTC().Format(time.RFC3339Nano) + "|" + last.ID
		out.More = n == ChangePage
	}
	return out, nil
}

// ErrBadCursor is a cursor we did not write. It is the caller's to fix, so it
// is a 400 rather than a silent full resync.
var ErrBadCursor = errors.New("bad cursor")

const firstCursorID = "00000000-0000-0000-0000-000000000000"

func parseCursor(cursor string) (time.Time, string, error) {
	if cursor == "" {
		return time.Time{}, firstCursorID, nil
	}
	at, id, found := strings.Cut(cursor, "|")
	if !found {
		return time.Time{}, "", ErrBadCursor
	}
	parsed, err := time.Parse(time.RFC3339Nano, at)
	if err != nil {
		return time.Time{}, "", ErrBadCursor
	}
	return parsed, id, nil
}
