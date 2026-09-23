package store_test

import (
	"encoding/json"
	"slices"
	"testing"
	"time"

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
