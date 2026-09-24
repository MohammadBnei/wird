package store_test

import (
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// The failure: a reader writes a bug report on a plane, the report takes a
// path of its own to the network instead of the outbox, and it is gone when
// the flush finally happens — or it arrives twice because that second path has
// no op id to be deduplicated by.
func TestAReportFlushedTwiceIsOneReportAndNotTwo(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-report-once")
	op := reportOp(opID(900), "bug", "the audio stops at the end of the set")

	if got := status(t, db, user, op); got != store.OpApplied {
		t.Fatalf("a report came back %q, so the reader's report never reached anyone", got)
	}
	if got := status(t, db, user, op); got != store.OpDuplicate {
		t.Fatalf("a replayed report came back %q, not duplicate", got)
	}
	if n := count(t, pool, `SELECT count(*) FROM reports`); n != 1 {
		t.Fatalf("one report written, %d stored: a retried flush is filing the same bug again", n)
	}
}

// The failure: reports are decided one-way, but a report row joins the change
// stream anyway. The device is handed back a row it has no table for, and the
// cursor moves past writes it has not applied while it works out what to do
// with it.
func TestAReportNeverComesBackDownTheChangeStreamOrMovesTheCursor(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-report-oneway")

	land(t, db, user, understood(opID(910), 1001, time.Now()))
	before := pull(t, db, user, "")

	land(t, db, user, reportOp(opID(911), "request", "a way to hide the translation"))

	after := pull(t, db, user, before.Cursor)
	if len(after.Changes) != 0 {
		t.Fatalf("the stream carried %d rows after a report was written: %+v", len(after.Changes), after.Changes)
	}
	if after.Cursor != before.Cursor {
		t.Fatalf("the cursor moved from %q to %q over a write nothing comes back for", before.Cursor, after.Cursor)
	}
}

// The failure: a report starts carrying the reader's practice — the aya they
// were on, the note they had open — because it was convenient to attach, and
// an operator reading reports is now reading somebody's devotion. The table is
// where that is stopped: it has no column to put it in, and the decoder
// refuses a body with a key the table has no room for.
func TestAReportCannotCarryAReadersNotesProgressOrCorpus(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-report-clean")

	var columns []string
	rows, err := pool.Query(t.Context(),
		`SELECT column_name FROM information_schema.columns WHERE table_name = 'reports'`)
	if err != nil {
		t.Fatalf("read the reports columns: %v", err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("read the reports columns: %v", err)
		}
		columns = append(columns, name)
	}
	slices.Sort(columns)
	want := []string{"app_version", "body", "corpus_version", "created_at", "id", "kind", "platform", "screen"}
	if !slices.Equal(columns, want) {
		t.Fatalf("reports carries %v where a report is only %v — a column here is a place somebody's practice can end up", columns, want)
	}

	smuggled := store.Op{ClientOpID: opID(920), Kind: "report_written", Body: json.RawMessage(
		`{"kind":"bug","body":"it crashed","app_version":"1.0.0","platform":"ios","screen":"prayer",` +
			`"corpus_version":1,"created_at":"2026-09-23T07:20:00Z","ayah_ids":[1001],"note":"my own words"}`)}
	if got := status(t, db, user, smuggled); got != store.OpRefused {
		t.Fatalf("a report carrying the reader's ayas and note came back %q, so their practice is now in the operator's list", got)
	}

	if n := count(t, pool, `SELECT count(*) FROM reports`); n != 0 {
		t.Fatalf("%d reports stored from a body that was refused", n)
	}
}

// The failure: a kind nobody triages, or an empty report, fills the list an
// operator reads — and the reader believes they were heard.
func TestAReportWithNoTextOrAKindNobodyTriagesIsRefused(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-report-kinds")

	for i, op := range []store.Op{
		reportOp(opID(930), "rant", "the whole thing"),
		reportOp(opID(931), "bug", ""),
	} {
		if got := status(t, db, user, op); got != store.OpRefused {
			t.Errorf("report %d came back %q, not refused", i, got)
		}
	}
}

func reportOp(id, kind, body string) store.Op {
	encoded, err := json.Marshal(map[string]any{
		"kind":           kind,
		"body":           body,
		"app_version":    "1.4.0",
		"platform":       "ios",
		"screen":         "prayer",
		"corpus_version": 1,
		"created_at":     time.Now().UTC(),
	})
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: "report_written", Body: encoded}
}

// The failure: a report row carries something that reaches the reader who sent
// it — as it did when the row was stored under the op id, which op_log holds
// against its author for the ninety days of the replay window — and an operator
// reading a private report can name the person who wrote it, and from that name
// read their notes, their progress and when they prayed.
//
// The column list cannot see this. Every column in reports is innocent; the
// link was the primary key's value. So this follows values rather than columns:
// it starts from what the report row holds and repeatedly takes every row
// anywhere in the database that shares one of those values, adding what that
// row holds. However many tables a link runs through and whatever it is made
// of, the reader's id or subject lands in that set if it is reachable at all.
func TestNoReportCanBeJoinedToTheReaderWhoSentIt(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-anwar-the-reader")

	land(t, db, user, understood(opID(940), 1001, time.Now()))
	land(t, db, user, prayedOp(opID(941), "mushaf", 1001, 1007, time.Now()))
	land(t, db, user, keptOp(opID(942), "I keep failing fajr"))
	land(t, db, user, reportOp(opID(943), "bug", "the audio stops at the end of the set"))

	author := map[string]string{user: "the reader's id", "sub-anwar-the-reader": "the reader's subject"}
	if trail := reaches(t, pool, reportRow(t, pool), author); trail != "" {
		t.Fatalf("a report reaches the person who wrote it: %s", trail)
	}

	// And the walk can see a link when there is one: the link just removed,
	// staged by hand, is the shape it has to keep catching.
	var id string
	if err := pool.QueryRow(t.Context(), `SELECT id FROM reports`).Scan(&id); err != nil {
		t.Fatalf("read the report id: %v", err)
	}
	exec(t, pool, `INSERT INTO op_log (user_id, client_op_id) VALUES ($1, $2)`, user, id)
	if trail := reaches(t, pool, reportRow(t, pool), author); trail == "" {
		t.Fatal("a report stored under its op id was not found to reach its author, so this test proves nothing")
	}
}

// reportRow is every value the one report in the database holds.
func reportRow(t *testing.T, pool *pgxpool.Pool) []string {
	t.Helper()
	rows := wholeDatabase(t, pool)["reports"]
	if len(rows) != 1 {
		t.Fatalf("expected one report to walk from, found %d", len(rows))
	}
	var values []string
	for _, v := range rows[0] {
		values = append(values, v)
	}
	return values
}

// reaches walks the whole database outwards from a set of values, stepping
// from any row that holds one of them to everything else that row holds, and
// answers how a target was reached — or "" when nothing connects them.
//
// ponytail: rescans every table per value, over a database holding a few dozen
// rows. Index the rows by value if a seed ever gets large.
func reaches(t *testing.T, pool *pgxpool.Pool, from []string, targets map[string]string) string {
	t.Helper()
	tables := wholeDatabase(t, pool)
	step := map[string]string{}
	prev := map[string]string{}

	var queue []string
	for _, v := range from {
		if linkable(v) && step[v] == "" {
			step[v] = "the report"
			queue = append(queue, v)
		}
	}
	for len(queue) > 0 {
		value := queue[0]
		queue = queue[1:]
		if name, ok := targets[value]; ok {
			return name + " by " + trail(step, prev, value)
		}
		for table, rows := range tables {
			for _, row := range rows {
				if !slices.Contains(slices.Collect(maps.Values(row)), value) {
					continue
				}
				for column, other := range row {
					if !linkable(other) || step[other] != "" {
						continue
					}
					step[other] = table + "." + column
					prev[other] = value
					queue = append(queue, other)
				}
			}
		}
	}
	return ""
}

// A value of eight characters or more is every id, subject and free-text field
// in this schema and none of its fixed words — a kind, a platform, a version.
// Following the short ones would chase coincidences: a corpus version of 1
// matches a set's ordinal, and that set has a reader on it.
//
// ponytail: a link built out of a short integer key would slip past this.
// Widen it if the schema ever grows one.
func linkable(v string) bool { return len(v) >= 8 }

func trail(step, prev map[string]string, value string) string {
	var parts []string
	for value != "" {
		parts = append(parts, fmt.Sprintf("%s (%s)", step[value], value))
		value = prev[value]
	}
	slices.Reverse(parts)
	return strings.Join(parts, " <- ")
}

// wholeDatabase reads every row of every table as text, so a walk over values
// does not have to know what any of the columns mean.
func wholeDatabase(t *testing.T, pool *pgxpool.Pool) map[string][]map[string]string {
	t.Helper()
	names, err := pool.Query(t.Context(),
		`SELECT table_name FROM information_schema.tables
		  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`)
	if err != nil {
		t.Fatalf("list the tables: %v", err)
	}
	var tables []string
	for names.Next() {
		var name string
		if err := names.Scan(&name); err != nil {
			t.Fatalf("list the tables: %v", err)
		}
		tables = append(tables, name)
	}
	if err := names.Err(); err != nil {
		t.Fatalf("list the tables: %v", err)
	}

	out := map[string][]map[string]string{}
	for _, table := range tables {
		rows, err := pool.Query(t.Context(), `SELECT to_jsonb(t) FROM `+table+` t`)
		if err != nil {
			t.Fatalf("read %s: %v", table, err)
		}
		for rows.Next() {
			var row map[string]any
			if err := rows.Scan(&row); err != nil {
				t.Fatalf("read %s: %v", table, err)
			}
			cells := map[string]string{}
			for column, value := range row {
				if value != nil {
					cells[column] = fmt.Sprint(value)
				}
			}
			out[table] = append(out[table], cells)
		}
		if err := rows.Err(); err != nil {
			t.Fatalf("read %s: %v", table, err)
		}
		rows.Close()
	}
	return out
}
