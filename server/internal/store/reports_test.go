package store_test

import (
	"encoding/json"
	"fmt"
	"maps"
	"math"
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
	want := []string{"app_version", "body", "corpus_version", "id", "kind", "platform", "screen", "written_on"}
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
// it, and an operator reading a private report can name the person who wrote
// it — and from that name read their notes, their progress and when they
// prayed.
//
// Three channels have been found here, one under the other, and not one of
// them was a column. The row's id was the op id, and op_log holds that against
// its author. Then the report row and that op_log row were written in one
// transaction, so both row versions carried the same xmin: a system column,
// which to_jsonb does not return, which is why the first version of this test
// passed while a join on xmin named three authors out of three. Then the day
// and time came from the device clock to the microsecond, and the op_log row
// nearest a report in time was its author's.
//
// So four things are walked and every one of them has to come up empty: the
// values, now with the system columns among them; the transaction ids, as a
// nearest rather than as an equality, because they are handed out in order and
// sitting beside a reader's op is as good as sharing one; the clock, the same
// way; and the order the rows sit in on disk, which a heap would otherwise
// leave as the order they arrived in. Each is then staged by hand, so a walk
// that has stopped working cannot read as a pass.
func TestNoReportCanBeJoinedToTheReaderWhoSentIt(t *testing.T) {
	db, pool := testenv.Postgres(t)

	// Six readers rather than one. A nearest walk always names somebody, so
	// what separates a channel from a coincidence is whether it names the
	// right reader every time.
	type sent struct {
		user, subject, body string
		at                  time.Time
	}
	var reports []sent
	author := map[string]string{}
	readers := map[string]string{}
	for i := range 6 {
		subject := fmt.Sprintf("sub-reporter-%d", i)
		user := reader(t, db, subject)
		land(t, db, user, understood(opID(940+i*10), 1001+i, time.Now()))
		land(t, db, user, keptOp(opID(941+i*10), fmt.Sprintf("reader %d keeps failing fajr", i)))
		body := fmt.Sprintf("report %d: the audio stops at the end of the set", i)
		op := onTheServersClock(t, pool, reportOp(opID(942+i*10), "bug", body))
		land(t, db, user, op)
		reports = append(reports, sent{user, subject, body, clockOf(t, op)})
		author[body] = user
		readers[user] = "the reader's id"
		readers[subject] = "the reader's subject"
	}

	for _, r := range reports {
		if trail := reaches(t, pool, reportRow(t, pool, r.body), readers); trail != "" {
			t.Fatalf("a report reaches the person who wrote it: %s", trail)
		}
	}

	// Every report is rewritten under one transaction id, so there is nothing
	// for a report's own id to be nearest to.
	if n := count(t, pool, `SELECT count(DISTINCT xmin::text)::int FROM reports`); n != 1 {
		t.Errorf("%d transaction ids over %d reports: a report that keeps its own sits beside its author's op_log row",
			n, len(reports))
	}
	txids := measured(t, pool, `SELECT body, (xmin::text::bigint)::float8 FROM reports`)
	opTxids := measured(t, pool, `SELECT user_id::text, (xmin::text::bigint)::float8 FROM op_log`)
	if named := namedBy(txids, opTxids, author); len(named) > 1 {
		t.Errorf("the nearest transaction id names the author of %v", named)
	}

	instants := measured(t, pool, `SELECT body, extract(epoch FROM written_on)::float8 FROM reports`)
	opInstants := measured(t, pool, `SELECT user_id::text, extract(epoch FROM applied_at)::float8 FROM op_log`)
	if named := namedBy(instants, opInstants, author); len(named) > 1 {
		t.Errorf("the op_log row nearest a report in time is its author's, for %v", named)
	}

	if disk, byID := order(t, pool, "ctid"), order(t, pool, "id"); !slices.Equal(disk, byID) {
		t.Errorf("the reports sit on disk in %v, which is not their id order %v, so the order they sit in is the order they arrived in",
			disk, byID)
	}

	// tableoid says which table a row is in and nothing about the row — until
	// reports are split across tables, which is the moment it starts saying
	// something about the row that landed in one of them.
	if n := count(t, pool, `SELECT count(DISTINCT tableoid::text)::int FROM reports`); n != 1 {
		t.Errorf("the reports are spread over %d tables, so which table one is in is a fact about it", n)
	}

	// From here the channels are staged by hand, so a walk that has stopped
	// working cannot read as a pass.

	arrived := make([]string, len(reports))
	for i, r := range reports {
		arrived[i] = r.body
	}
	exec(t, pool, regroupedIn("array_position($1::text[], body)"), arrived)
	if disk := order(t, pool, "ctid"); !slices.Equal(disk, arrived) {
		t.Fatalf("the rows would not sit in the order they arrived (%v), so their order on disk is not being read", disk)
	}
	exec(t, pool, regroupedIn("id DESC"))
	if disk, byID := order(t, pool, "ctid"), order(t, pool, "id"); slices.Equal(disk, byID) {
		t.Fatal("rows written in the reverse of their id order still read as being in it, so the walk over their order proves nothing")
	}

	// The clock, as it stood before the column became a date: fed the device
	// times the reports arrived carrying, the same walk names every author.
	real := make([]pair, 0, len(reports))
	for _, r := range reports {
		real = append(real, pair{r.body, float64(r.at.UnixNano()) / 1e9})
	}
	if named := namedBy(real, opInstants, author); len(named) != len(reports) {
		t.Fatalf("fed the device times the reports carried, the walk named %d of %d authors, so the walk over the clock proves nothing",
			len(named), len(reports))
	}

	// The value join, as it stood before 00006: the report under its op id.
	var id string
	if err := pool.QueryRow(t.Context(),
		`SELECT id FROM reports WHERE body = $1`, reports[0].body).Scan(&id); err != nil {
		t.Fatalf("read a report id: %v", err)
	}
	exec(t, pool, `INSERT INTO op_log (user_id, client_op_id) VALUES ($1, $2)`, reports[0].user, id)
	if trail := reaches(t, pool, reportRow(t, pool, reports[0].body), readers); trail == "" {
		t.Fatal("a report stored under its op id was not found to reach its author, so the walk over the values proves nothing")
	}

	// The transaction id, as it stood before 00007: a report and an op_log row
	// written together, which leaves both row versions carrying one xmin.
	shared := "a report written inside its author's own transaction"
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatalf("stage a shared transaction: %v", err)
	}
	defer func() { _ = tx.Rollback(t.Context()) }()
	if _, err := tx.Exec(t.Context(),
		`INSERT INTO op_log (user_id, client_op_id) VALUES ($1, gen_random_uuid())`, reports[1].user); err != nil {
		t.Fatalf("stage a shared transaction: %v", err)
	}
	if _, err := tx.Exec(t.Context(), `
		INSERT INTO reports (id, kind, body, app_version, platform, screen, corpus_version, written_on)
		VALUES (gen_random_uuid(), 'bug', $1, '1.4.0', 'ios', 'prayer', 1, current_date)`, shared); err != nil {
		t.Fatalf("stage a shared transaction: %v", err)
	}
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatalf("stage a shared transaction: %v", err)
	}
	if trail := reaches(t, pool, reportRow(t, pool, shared), readers); trail == "" {
		t.Fatal("a report sharing a transaction with an op_log row was not found to reach its author, so the walk over the system columns proves nothing")
	}
}

// onTheServersClock puts the server's own time on a report op. That is the
// case the clock channel is about: a device whose clock is right, flushing
// within two minutes of writing, so that the time the report carries and the
// time its flush landed are the same time read off the same clock.
func onTheServersClock(t *testing.T, pool *pgxpool.Pool, op store.Op) store.Op {
	t.Helper()
	var now time.Time
	if err := pool.QueryRow(t.Context(), `SELECT now()`).Scan(&now); err != nil {
		t.Fatalf("read the server clock: %v", err)
	}
	var fields map[string]any
	if err := json.Unmarshal(op.Body, &fields); err != nil {
		t.Fatalf("reread a report body: %v", err)
	}
	fields["created_at"] = now.UTC()
	encoded, err := json.Marshal(fields)
	if err != nil {
		t.Fatalf("rewrite a report body: %v", err)
	}
	op.Body = encoded
	return op
}

// clockOf is the device time a report op carries, which is what the column
// kept to the microsecond before it became a date.
func clockOf(t *testing.T, op store.Op) time.Time {
	t.Helper()
	var b struct {
		CreatedAt time.Time `json:"created_at"`
	}
	if err := json.Unmarshal(op.Body, &b); err != nil {
		t.Fatalf("reread a report body: %v", err)
	}
	return b.CreatedAt
}

// regroupedIn is the rewrite applyReport does, with the order it lays the rows
// down in left to the caller, so a test can put them back the way a heap
// leaves them.
func regroupedIn(order string) string {
	return `
WITH gone AS (DELETE FROM reports RETURNING *)
INSERT INTO reports (id, kind, body, app_version, platform, screen, corpus_version, written_on)
SELECT id, kind, body, app_version, platform, screen, corpus_version, written_on
  FROM gone ORDER BY ` + order
}

// order is the report bodies as one ordering puts them.
func order(t *testing.T, pool *pgxpool.Pool, by string) []string {
	t.Helper()
	rows, err := pool.Query(t.Context(), `SELECT body FROM reports ORDER BY `+by)
	if err != nil {
		t.Fatalf("read the reports by %s: %v", by, err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			t.Fatalf("read the reports by %s: %v", by, err)
		}
		out = append(out, body)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("read the reports by %s: %v", by, err)
	}
	return out
}

// A pair is one row placed on one measure: what it is, and where it sits.
type pair struct {
	key string
	at  float64
}

func measured(t *testing.T, pool *pgxpool.Pool, sql string) []pair {
	t.Helper()
	rows, err := pool.Query(t.Context(), sql)
	if err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	defer rows.Close()
	var out []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.key, &p.at); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	return out
}

// namedBy takes, for each report, the reader whose op_log row sits nearest it
// on one measure, and answers which reports that names correctly. Some reader
// is always nearest, so one right answer out of six is what a measure that
// carries nothing looks like. A measure that is right more often than that is
// carrying the author.
func namedBy(reports, log []pair, author map[string]string) []string {
	var named []string
	for _, r := range reports {
		best, nearest, tied := "", math.Inf(1), false
		for _, row := range log {
			switch d := math.Abs(row.at - r.at); {
			case d < nearest:
				best, nearest, tied = row.key, d, false
			case d == nearest && row.key != best:
				tied = true
			}
		}
		if !tied && best == author[r.key] {
			named = append(named, r.key)
		}
	}
	slices.Sort(named)
	return named
}

// reportRow is every value the report carrying this body holds.
func reportRow(t *testing.T, pool *pgxpool.Pool, body string) []string {
	t.Helper()
	for _, row := range wholeDatabase(t, pool)["reports"] {
		if row["body"] != body {
			continue
		}
		var values []string
		for _, v := range row {
			values = append(values, v)
		}
		return values
	}
	t.Fatalf("no report carrying %q to walk from", body)
	return nil
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
// A transaction id is followed however short it is: it is four digits in a
// fresh database, and it is exactly the link this test exists to catch.
//
// ponytail: a link built out of a short integer key would slip past this.
// Widen it if the schema ever grows one.
func linkable(v string) bool { return len(v) >= 8 || strings.HasPrefix(v, "tx:") }

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
//
// to_jsonb returns the columns and only the columns, which is what let a join
// on xmin stand while this test passed. The system columns are added by hand,
// each spelled so that it can only match the same system column: a transaction
// id is the database's own and matches across tables, which is the channel; a
// ctid is a place in one table's heap and means nothing in another's; a
// tableoid names the table. xmax is left out because it is zero on every row
// that is not being deleted, so following it would join everything to
// everything.
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
		rows, err := pool.Query(t.Context(), fmt.Sprintf(`
			SELECT to_jsonb(t) || jsonb_build_object(
			         'xmin', 'tx:' || t.xmin::text,
			         'ctid', 'ctid:%[1]s:' || t.ctid::text,
			         'tableoid', 'table:' || t.tableoid::text)
			  FROM %[1]s t`, table))
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
