package store_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// Health answers about everybody or it does not answer. If this stops
// compiling because it grew a reader to ask about, the rule broke here first.
var _ func(*store.Store, context.Context) (store.Health, error) = (*store.Store).Health

// The failure this file exists for: somebody adds "and filter it by reader" to
// a dashboard query, because on the day it is convenient it is only one WHERE,
// and Wird — which knows which ayas a person understood, what they wrote and
// when they prayed — becomes a way to watch one named person's devotion.
//
// So every statement the dashboard can run is held to four rules it can be read
// for: it binds no argument, so a call site cannot narrow it; it never names a
// reader, so the text cannot narrow it either; it tallies rather than lists;
// and every value that comes back is a number. Reports are the one thing that
// is not a number, and they are read by a method of their own, from a table
// with no reader in it and no id that reaches one — that is what
// TestAReportCannotCarryAReadersNotesProgressOrCorpus and
// TestNoReportCanBeJoinedToTheReaderWhoSentIt hold.
//
// Those four are read off the text, and reading catches only what is spelled
// out: `SELECT count(*) FROM users GROUP BY id` passes all four and answers one
// row per reader. So the statements are held to their shape as well, by running
// them: a reader added to the database must not add a row to any answer. That
// is what separates a tally of everybody from a tally per person, whatever the
// key is called.
func TestNoDashboardAggregateCanBeNarrowedToOneNamedReader(t *testing.T) {
	db, pool := testenv.Postgres(t)
	seedTwoReadersWithPractice(t, db)

	rows := map[string]int{}
	for _, sql := range store.AdminAggregates {
		short := strings.Join(strings.Fields(sql), " ")
		if strings.Contains(sql, "$") {
			t.Errorf("an aggregate binds an argument, so a caller can point it at one reader: %s", short)
			continue
		}
		for _, named := range []string{"user_id", "oidc_subject", "users.id"} {
			if strings.Contains(sql, named) {
				t.Errorf("an aggregate names %s, which is one WHERE away from a single reader: %s", named, short)
			}
		}
		if !strings.Contains(sql, "count(") && !strings.Contains(sql, "sum(") {
			t.Errorf("an aggregate that neither counts nor sums is a list of rows about somebody: %s", short)
		}

		// And it really is a tally when it runs, not only when it is read.
		for _, row := range answer(t, pool, sql) {
			for _, v := range row {
				switch v.(type) {
				case int64, int32, int16, int, float64:
				default:
					t.Errorf("an aggregate answered with %T (%v), and a number is the only answer that cannot be somebody: %s", v, v, short)
				}
			}
			rows[sql]++
		}
	}

	// A third reader whose practice is a copy of the second's: nothing new is
	// being counted, there is only one more person doing it.
	seedReaderWithPractice(t, db, "sub-admin-three", 820, 1003, 4)

	for _, sql := range store.AdminAggregates {
		short := strings.Join(strings.Fields(sql), " ")
		if grew := len(answer(t, pool, sql)); grew != rows[sql] {
			t.Errorf("an aggregate answered %d rows where it answered %d before a reader was added, so it is a row per person however its key is spelled: %s",
				grew, rows[sql], short)
		}
	}
}

func answer(t *testing.T, pool *pgxpool.Pool, sql string) [][]any {
	t.Helper()
	rows, err := pool.Query(t.Context(), sql)
	if err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	defer rows.Close()

	var out [][]any
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
		out = append(out, values)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	return out
}

// The failure: the dashboard's numbers are one reader's rather than everyone's,
// or they are silently zero because nothing ever increments them — an operator
// then sees a healthy system while writes are being lost.
func TestTheDashboardCountsEveryReadersPrayersAndEveryLostWrite(t *testing.T) {
	db, pool := testenv.Postgres(t)
	seedTwoReadersWithPractice(t, db)

	// A server having a bad minute is not something a test can stage against a
	// healthy Postgres, so the row applyOne would write is written here and the
	// dashboard is held to reading it.
	exec(t, pool, `INSERT INTO sync_outcomes (day, kind, status, ops)
	               VALUES (current_date, 'set_prayed', 'failed', 3)`)

	health, err := db.Health(t.Context())
	if err != nil {
		t.Fatalf("health: %v", err)
	}
	if health.Readers != 2 {
		t.Errorf("counted %d readers where two have accounts", health.Readers)
	}
	if health.SetsPrayed != 2 {
		t.Errorf("counted %d sets prayed where two were prayed", health.SetsPrayed)
	}
	if health.SyncFailures != 3 {
		t.Errorf("counted %d sync failures where three were recorded", health.SyncFailures)
	}
	if health.ParkedWrites != 2 {
		t.Errorf("counted %d parked writes where two were refused, so an operator cannot see writes being lost", health.ParkedWrites)
	}
	if len(health.CorpusVersions) != 2 ||
		health.CorpusVersions[0] != (store.FieldVersion{CorpusVersion: 1, Reports: 1}) ||
		health.CorpusVersions[1] != (store.FieldVersion{CorpusVersion: 4, Reports: 1}) {
		t.Errorf("the corpus versions in the field came back %+v, so a report cannot be tied to a build", health.CorpusVersions)
	}

	// A report is kept to the day it was written, so two that landed in the
	// same test second cannot say which came first. One is moved back a week,
	// which is the distance an operator's list is actually ordered over.
	exec(t, pool, `UPDATE reports SET written_on = current_date - 7 WHERE corpus_version = 1`)

	reports, err := db.Reports(t.Context(), 0)
	if err != nil {
		t.Fatalf("reports: %v", err)
	}
	if len(reports) != 2 {
		t.Fatalf("two readers reported and the list holds %d", len(reports))
	}
	if reports[0].WrittenOn.Before(reports[1].WrittenOn) {
		t.Errorf("the list is oldest first, so the report that just came in is at the bottom")
	}
}

// The failure: a device gone wrong sends a kind nobody has ever heard of on
// every flush, and the one table that is supposed to be a handful of counters
// grows a row per word it invents.
func TestAnOpKindNobodyRecognisesIsCountedUnderOneWordRatherThanItsOwn(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-junk-kinds")

	for i, kind := range []string{"nonsense", "more-nonsense"} {
		op := store.Op{ClientOpID: opID(960 + i), Kind: kind, Body: json.RawMessage(`{}`)}
		if got := status(t, db, user, op); got != store.OpRefused {
			t.Fatalf("a kind the server has never heard of came back %q", got)
		}
	}
	if n := count(t, pool, `SELECT count(*) FROM sync_outcomes`); n != 1 {
		t.Fatalf("two invented kinds made %d counter rows, and the table grows with whatever a device says", n)
	}
	if n := count(t, pool, `SELECT ops::int FROM sync_outcomes WHERE kind = 'unknown'`); n != 2 {
		t.Fatalf("the unknown kinds counted %d times, not twice", n)
	}
}

// Two readers, each with the practice a dashboard must never be able to single
// out: ayas understood, a set prayed, a note kept, a report sent, and a write
// the server refused.
func seedTwoReadersWithPractice(t *testing.T, db *store.Store) {
	t.Helper()
	seedReaderWithPractice(t, db, "sub-admin-one", 800, 1001, 1)
	seedReaderWithPractice(t, db, "sub-admin-two", 810, 1002, 4)
	// A report is not in the table the dashboard reads until a sweep puts it
	// there, which is the whole of what separates its write from its author's.
	sweep(t, db)
}

func seedReaderWithPractice(t *testing.T, db *store.Store, subject string, base, ayah, corpusVersion int) {
	t.Helper()
	user := reader(t, db, subject)
	land(t, db, user, understood(opID(base), ayah, time.Now()))
	land(t, db, user, prayedOp(opID(base+1), "mushaf", 1001, 1007, time.Now()))
	land(t, db, user, keptOp(opID(base+2), "what the reader wrote down"))

	report := reportOp(opID(base+3), "bug", "the audio stops at the end of the set")
	report.Body = withCorpusVersion(t, report.Body, corpusVersion)
	land(t, db, user, report)

	bad := store.Op{ClientOpID: opID(base + 4), Kind: "ayah_understood", Body: json.RawMessage(`{"nope":1}`)}
	if got := status(t, db, user, bad); got != store.OpRefused {
		t.Fatalf("the seeded bad write came back %q, not refused", got)
	}
}

func keptOp(id, body string) store.Op {
	encoded, err := json.Marshal(map[string]any{
		"id": "6ba7b810-9dad-11d1-80b4-" + id[len(id)-12:], "kind": "note",
		"ayah_id": nil, "root_letters": nil, "body": body, "tags": []string{},
		"created_at": time.Now().UTC(), "updated_at": time.Now().UTC(),
	})
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: "kept_upsert", Body: encoded}
}

func withCorpusVersion(t *testing.T, body json.RawMessage, version int) json.RawMessage {
	t.Helper()
	var fields map[string]any
	if err := json.Unmarshal(body, &fields); err != nil {
		t.Fatalf("reread a report body: %v", err)
	}
	fields["corpus_version"] = version
	encoded, err := json.Marshal(fields)
	if err != nil {
		t.Fatalf("rewrite a report body: %v", err)
	}
	return encoded
}
