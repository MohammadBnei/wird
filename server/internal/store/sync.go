package store

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
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

// applyOne is the attempt plus its bookkeeping: a write the reader is about to
// lose is counted, in aggregate, so an operator can see that syncs are failing
// without being able to see whose.
func (s *Store) applyOne(ctx context.Context, userID string, op Op) (OpResult, error) {
	result, err := s.attempt(ctx, userID, op)
	if err != nil {
		return OpResult{}, err
	}
	if result.Status == OpRefused || result.Status == OpFailed {
		s.countOutcome(ctx, op.Kind, result.Status)
	}
	return result, nil
}

// attempt writes the op id and the op's effect in one transaction. They
// commit together or not at all: an op id recorded for a write that rolled
// back would make the retry look like a replay and lose the write for good.
func (s *Store) attempt(ctx context.Context, userID string, op Op) (OpResult, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return OpResult{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	result := applyInTx(ctx, tx, s.pool, userID, op)
	if result.Status != OpApplied {
		return result, nil
	}
	if err := tx.Commit(ctx); err != nil {
		return classify(op, err), nil
	}
	return result, nil
}

// applyInTx is everything but the commit. It is a function of its own so a
// test can hold the transaction open and choose the moment it commits, which
// is the only way to stage two writes landing at once.
//
// outside is the pool, for the one op whose effect must not commit in tx.
func applyInTx(ctx context.Context, tx pgx.Tx, outside *pgxpool.Pool, userID string, op Op) OpResult {
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
	if err := applyKind(ctx, tx, outside, userID, op); err != nil {
		return classify(op, err)
	}
	return OpResult{ClientOpID: op.ClientOpID, Status: OpApplied}
}

// lockReader is what makes the commit order and the sequence order the same
// order, and it is not optional. A sequence number is handed out when the
// INSERT runs, not when it commits, so two writes in flight at once can
// commit in the opposite order to their numbers — and a device whose cursor
// has already passed the lower number never hears about that row again. That
// is the very failure this sequence exists to fix, one layer down.
//
// The lock is held until the transaction ends, so for one reader the write
// holding the lower number is always the write that committed first. Readers
// do not contend with each other; two whose ids happen to hash together only
// wait for one another, which costs nothing and breaks nothing.
//
// ponytail: one lock per reader, so one reader's writes land one at a time.
// A reader has a phone and a tablet, not a fleet. If that ever stops being
// true, the upgrade is to publish a row only once every transaction below it
// has committed — a watermark from pg_snapshot_xmin(pg_current_snapshot()) —
// rather than to widen this lock.
func lockReader(ctx context.Context, tx pgx.Tx, userID string) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, userID)
	return err
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

func applyKind(ctx context.Context, tx pgx.Tx, outside *pgxpool.Pool, userID string, op Op) error {
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
		return applySetPrayed(ctx, tx, userID, op)
	case "prefs_set":
		return applyPrefsSet(ctx, tx, userID, op.Body)
	case "report_written":
		return applyReport(ctx, outside, op)
	default:
		return refuse("unknown kind %q", op.Kind)
	}
}

// opKinds is the same list the switch above answers to, and it exists because
// a kind is whatever the device said it was. Counting an outcome under an
// unrecognised word would let one device gone wrong grow sync_outcomes without
// bound, so anything not in this list is counted as "unknown".
var opKinds = []string{
	"ayah_understood", "kept_upsert", "kept_delete",
	"set_recorded", "set_prayed", "prefs_set", "report_written",
}

// countOutcome is best effort on purpose: a counter that cannot be incremented
// is not a reason to fail a reader's sync, and the sync's own answer has
// already been decided by the time it runs.
func (s *Store) countOutcome(ctx context.Context, kind, status string) {
	if !slices.Contains(opKinds, kind) {
		kind = "unknown"
	}
	_, _ = s.pool.Exec(ctx, `
		INSERT INTO sync_outcomes (day, kind, status, ops) VALUES (current_date, $1, $2, 1)
		ON CONFLICT (day, kind, status) DO UPDATE SET ops = sync_outcomes.ops + 1`, kind, status)
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
		if !isAya(id) {
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
		       tags = EXCLUDED.tags, updated_at = EXCLUDED.updated_at,
		       seq = nextval('change_seq')
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
		       updated_at = GREATEST(updated_at, $3),
		       seq = nextval('change_seq')
		 WHERE id = $2 AND user_id = $1`, userID, b.ID, b.DeletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return refuse("no kept item %s", b.ID)
	}
	return nil
}

// setNamespace is the uuidv5 namespace a set id is derived in. It is itself
// uuidv5(NameSpaceURL, "https://wird.bnei.dev/set") so that the value can be
// recomputed rather than trusted, and every device must use this same literal.
var setNamespace = uuid.MustParse("302f8902-5d26-53eb-bfc6-b45ac9fff0c5")

// SetID is a set's identity, and it is a pure function of what the set is:
// the range of ayas and the order they are read in. Nothing about where the
// reader stands is in it. Because it is derived rather than minted, a
// reinstall recomputes the same id, a phone and a tablet agree on it without
// ever speaking, and the prayers on one set can be counted.
func SetID(readingOrder string, startAyahID, endAyahID int) string {
	key := fmt.Sprintf("%s:%d:%d", readingOrder, startAyahID, endAyahID)
	return uuid.NewSHA1(setNamespace, []byte(key)).String()
}

// readingOrders are the only two words a reading order is ever spelled with.
// The device holds them as an enum; here they were a free string that nothing
// above the column constraint looked at, which refused a third spelling with
// "it does not fit what is already recorded" — true, and no help to the
// device that sent it. A set id is derived from this word, so a wrong
// spelling is not a bad value: it is a set no other device can name.
var readingOrders = []string{"mushaf", "nuzul"}

func checkReadingOrder(order string) error {
	if !slices.Contains(readingOrders, order) {
		return refuse("%q is not a reading order", order)
	}
	return nil
}

// isAya says whether a number is one of the corpus's own natural keys. An id
// outside them would count something that does not exist towards the numbers
// this app exists to show.
func isAya(id int) bool {
	return id/1000 >= 1 && id/1000 <= 114 && id%1000 >= 1
}

// upsertSet writes the set if this reader does not have it yet, and numbers
// it here rather than on the device. A device-chosen ordinal collides on the
// second set, on a reinstall and on a second device, and the collision is
// refused forever; the reader's own set count is ours to keep.
//
// MAX+1 is safe because applyInTx holds this reader's advisory lock for the
// whole transaction, so their writes land one at a time.
func upsertSet(ctx context.Context, tx pgx.Tx, userID, setID string,
	startAyahID, endAyahID int, readingOrder string, createdAt time.Time,
) error {
	if !isAya(startAyahID) || !isAya(endAyahID) || endAyahID < startAyahID {
		return refuse("%d to %d is not a range of ayas", startAyahID, endAyahID)
	}
	if err := checkReadingOrder(readingOrder); err != nil {
		return err
	}
	// The id is recomputed rather than trusted. A device that derives ids
	// differently from this server is a bug that would otherwise surface
	// months later as two sets for one range.
	if want := SetID(readingOrder, startAyahID, endAyahID); want != setID {
		return refuse("the set id does not match the range and order it carries")
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order, created_at)
		SELECT $1, $2, COALESCE(MAX(ordinal), 0) + 1, $3, $4, $5, $6
		  FROM sets WHERE user_id = $2
		ON CONFLICT (user_id, id) DO NOTHING`,
		setID, userID, startAyahID, endAyahID, readingOrder, createdAt)
	return err
}

// applySetRecorded is the old shape, kept so a phone that has not updated
// still lands its queue. Its ids are minted, not derived, so they are not
// checked against the range — refusing them would dead-letter exactly the
// writes this compatibility exists to save. New clients send set_prayed
// alone. Any ordinal in the body is read and ignored: dropping the field
// from this struct would make DisallowUnknownFields refuse the whole op.
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
		SELECT $1, $2, COALESCE(MAX(ordinal), 0) + 1, $3, $4, $5, $6
		  FROM sets WHERE user_id = $2
		ON CONFLICT (user_id, id) DO NOTHING`,
		b.ID, userID, b.StartAyahID, b.EndAyahID, b.ReadingOrder, b.CreatedAt)
	return err
}

// The prayer, and the set it was prayed on, in one transaction. They used to
// be two ops, and the pair was unsafe: the device's queue is ordered by a
// timestamp with a random-uuid tiebreak, so which of them reached here first
// was a coin flip, and a set that failed for a minute made its prayer refused
// forever. One op has no order to get wrong.
//
// A body carrying the range upserts the set; a body without one is the old
// shape, where the set arrived as its own op and must already be here.
func applySetPrayed(ctx context.Context, tx pgx.Tx, userID string, op Op) error {
	var b struct {
		ID           string    `json:"id"`
		SetID        string    `json:"set_id"`
		StartAyahID  int       `json:"start_ayah_id"`
		EndAyahID    int       `json:"end_ayah_id"`
		ReadingOrder string    `json:"reading_order"`
		PrayerName   string    `json:"prayer_name"`
		PrayedAt     time.Time `json:"prayed_at"`
	}
	if err := decode(op.Body, &b); err != nil {
		return err
	}
	if b.StartAyahID != 0 || b.EndAyahID != 0 || b.ReadingOrder != "" {
		if err := upsertSet(ctx, tx, userID, b.SetID,
			b.StartAyahID, b.EndAyahID, b.ReadingOrder, b.PrayedAt); err != nil {
			return err
		}
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
	// The op id is the prayer's id when the device does not name one, so a
	// replay lands on the same row even after the op log has been pruned.
	id := b.ID
	if id == "" {
		id = op.ClientOpID
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO set_prayers (id, set_id, user_id, prayer_name, prayed_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO NOTHING`,
		id, b.SetID, userID, b.PrayerName, b.PrayedAt)
	return err
}

// The one apply that is not handed the reader, because a report has nowhere
// to put one. It reaches the same table an operator reads, so the reader it
// came from must not be recoverable from it — and the column list is the
// smallest part of that. Three channels have been found under it so far, each
// one proved against a real database:
//
// The row's id used to be the op id, and op_log holds that against the reader
// who sent it for the ninety days of OpLogWindow. So the id is minted here.
//
// The report used to be written in the op's own transaction, and two row
// versions written in one transaction carry the same xmin — a system column
// any role that can SELECT can read. So it is written on the pool, in a
// transaction of its own, while the op's transaction still holds this reader's
// advisory lock and has not committed. If this fails, the op id rolls back
// with it and the device's retry is clean; if that commit fails after this
// one, the device files a duplicate rather than losing the report.
//
// Separate transactions are not enough by themselves, because transaction ids
// are handed out in order and a report that commits between two of a reader's
// ops still sits next to them. So the write also regroups: every report row is
// deleted and written again in one transaction, which leaves them all carrying
// that transaction's id and none of them nearer their author's op_log row than
// the rest. Ordered by id, because a heap appends and the order rows sit in on
// disk would otherwise be the order they arrived in.
//
// The device's clock is kept to the day, because the op_log row nearest a
// microsecond-accurate time was its author's.
//
// ponytail: the whole table is rewritten on every report. Reports arrive a
// handful a day and there is no second writer to contend with. Regroup on the
// ticker alone, and wear the window it leaves, if that ever stops being true.
func applyReport(ctx context.Context, pool *pgxpool.Pool, op Op) error {
	var b struct {
		Kind          string    `json:"kind"`
		Body          string    `json:"body"`
		AppVersion    string    `json:"app_version"`
		Platform      string    `json:"platform"`
		Screen        string    `json:"screen"`
		CorpusVersion int       `json:"corpus_version"`
		CreatedAt     time.Time `json:"created_at"`
	}
	if err := decode(op.Body, &b); err != nil {
		return err
	}
	if b.CreatedAt.IsZero() {
		b.CreatedAt = time.Now().UTC()
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `
		INSERT INTO reports (id, kind, body, app_version, platform, screen, corpus_version, written_on)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		uuid.NewString(), b.Kind, b.Body, b.AppVersion, b.Platform, b.Screen,
		b.CorpusVersion, b.CreatedAt.UTC()); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, regroupReportsSQL); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// regroupReportsSQL rewrites every report row in one statement, so that they
// all carry one transaction id and sit on disk in the order of their ids
// rather than the order they were written.
const regroupReportsSQL = `
WITH gone AS (DELETE FROM reports RETURNING *)
INSERT INTO reports (id, kind, body, app_version, platform, screen, corpus_version, written_on)
SELECT id, kind, body, app_version, platform, screen, corpus_version, written_on
  FROM gone ORDER BY id`

// RegroupReports runs that rewrite on its own. Every report write already
// does it, which leaves the shared transaction id sitting next to the op_log
// row of whoever reported last. A pass on the ticker moves it to a moment
// that belongs to nobody in particular.
func (s *Store) RegroupReports(ctx context.Context) error {
	_, err := s.pool.Exec(ctx, regroupReportsSQL)
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
	if err := checkReadingOrder(b.ReadingOrder); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO user_prefs (user_id, reading_order, updated_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE
		   SET reading_order = EXCLUDED.reading_order, updated_at = EXCLUDED.updated_at,
		       seq = nextval('change_seq')
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
SELECT kind, id, at, row, seq FROM (
	SELECT 'ayah_understood' AS kind, id, understood_at AS at,
	       jsonb_build_object('ayah_id', ayah_id, 'understood_at', understood_at) AS row, seq
	  FROM ayah_understood WHERE user_id = $1 AND seq > $2
	UNION ALL
	SELECT 'kept_items', id, updated_at,
	       jsonb_build_object('id', id, 'kind', kind, 'ayah_id', ayah_id,
	                          'root_letters', root_letters, 'body', body,
	                          'tags', to_jsonb(tags), 'created_at', created_at,
	                          'updated_at', updated_at, 'deleted_at', deleted_at), seq
	  FROM kept_items WHERE user_id = $1 AND seq > $2
	UNION ALL
	SELECT 'sets', id, created_at,
	       jsonb_build_object('id', id, 'ordinal', ordinal, 'start_ayah_id', start_ayah_id,
	                          'end_ayah_id', end_ayah_id, 'reading_order', reading_order,
	                          'created_at', created_at), seq
	  FROM sets WHERE user_id = $1 AND seq > $2
	UNION ALL
	SELECT 'set_prayers', id, prayed_at,
	       jsonb_build_object('id', id, 'set_id', set_id, 'prayer_name', prayer_name,
	                          'prayed_at', prayed_at), seq
	  FROM set_prayers WHERE user_id = $1 AND seq > $2
	UNION ALL
	SELECT 'user_prefs', user_id, updated_at,
	       jsonb_build_object('reading_order', reading_order, 'updated_at', updated_at), seq
	  FROM user_prefs WHERE user_id = $1 AND seq > $2
) changed
 ORDER BY seq
 LIMIT $3`

// Changes is the pull half. The cursor is a position in the server's own
// commit order, never in the device's clock: a write made offline on Monday
// and flushed on Friday carries Monday's instant, and a cursor that walked
// timestamps would have passed it on Wednesday and never come back for it.
// The row's own timestamps still travel in the payload — they are what
// last-write-wins reconciles with — they just do not decide what is sent.
func (s *Store) Changes(ctx context.Context, userID, cursor string) (Changes, error) {
	since, err := parseCursor(cursor)
	if err != nil {
		return Changes{}, err
	}
	out := Changes{Changes: []Change{}, Cursor: cursor}
	rows, err := s.pool.Query(ctx, changesSQL, userID, since, ChangePage)
	if err != nil {
		return out, err
	}
	defer rows.Close()

	var last int64
	for rows.Next() {
		var c Change
		var seq int64
		if err := rows.Scan(&c.Kind, &c.ID, &c.At, &c.Row, &seq); err != nil {
			return out, err
		}
		out.Changes = append(out.Changes, c)
		last = seq
	}
	if err := rows.Err(); err != nil {
		return out, err
	}
	if n := len(out.Changes); n > 0 {
		out.Cursor = formatCursor(last)
		out.More = n == ChangePage
	}
	return out, nil
}

// ErrBadCursor is a cursor we did not write. It is the caller's to fix, so it
// is a 400 rather than a silent full resync.
var ErrBadCursor = errors.New("bad cursor")

// A cursor is prefixed rather than a bare number so that a position a device
// invented, and a cursor left over from an older server, are both refused
// instead of read as somewhere in the stream.
const cursorPrefix = "seq:"

func formatCursor(seq int64) string {
	return cursorPrefix + strconv.FormatInt(seq, 10)
}

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
