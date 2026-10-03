package store_test

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// verdictOp is the thumb on a root's sense as report.dart sends it.
func verdictOp(id, verdict, root, locale, senseHash string) store.Op {
	encoded, err := json.Marshal(map[string]any{
		"kind": "improvement", "body": "sense " + verdict + ": " + root,
		"app_version": "1.4.0", "platform": "android", "screen": "root",
		"corpus_version": 4, "sense_version": "1-047d1760906cf3723679bc6dd351c0a7",
		"locale": locale, "sense_hash": senseHash,
		"created_at": time.Now().UTC(),
	})
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: "report_written", Body: encoded}
}

// hashOf is the sense_hash a device sends for the text it showed.
func hashOf(text string) string {
	sum := sha256.Sum256([]byte(text))
	return hex.EncodeToString(sum[:])[:12]
}

// The failure: the tally counts every bad thumb a root ever got, so a sense
// corrected last month still tops the list on the verdicts against the old
// text, and the one readers are judging wrong today sits under it. And the
// other half: a French reader's thumb is counted against the English sentence.
func TestABadVerdictOnTextAlreadyCorrectedDoesNotCountAgainstTheTextServedToday(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-verdicts")
	exec(t, pool, `INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES
		('كتب', 'writing', 'écriture'), ('علم', 'knowing', 'savoir')`)

	for _, op := range []store.Op{
		verdictOp(opID(1100), "bad", "كتب", "en", hashOf("an old sentence since corrected")),
		verdictOp(opID(1101), "bad", "كتب", "en", hashOf("an old sentence since corrected")),
		verdictOp(opID(1102), "good", "كتب", "en", hashOf("writing")),
		verdictOp(opID(1103), "bad", "علم", "en", hashOf("knowing")),
		verdictOp(opID(1104), "bad", "علم", "fr", hashOf("savoir")),
		verdictOp(opID(1105), "bad", "علم", "fr", hashOf("knowing")),
	} {
		land(t, db, user, op)
	}
	sweep(t, db)

	got, err := db.SenseVerdicts(t.Context())
	if err != nil {
		t.Fatalf("sense verdicts: %v", err)
	}
	want := []store.SenseVerdict{
		{Root: "علم", Locale: "fr", Good: 0, Bad: 2, BadOnCurrent: 1},
		{Root: "علم", Locale: "en", Good: 0, Bad: 1, BadOnCurrent: 1},
		{Root: "كتب", Locale: "en", Good: 1, Bad: 2, BadOnCurrent: 0},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("the tally came back\n%+v\nwhere the text served today is judged\n%+v", got, want)
	}
}

// The failure: the root in a verdict is read out of a body a stranger typed,
// and the tally hands it to the operator's page as though it were one of ours.
// The join on root_senses is what stops that, so this sends a root nobody
// wrote a sense for, and a real root with something trailing it.
func TestAVerdictOnARootWeNeverWroteNeverReachesTheTally(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-forged-verdict")
	exec(t, pool, `INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES ('كتب', 'writing', 'écriture')`)

	land(t, db, user, verdictOp(opID(1110), "bad", `x"; rm -rf /`, "en", ""))
	land(t, db, user, verdictOp(opID(1111), "bad", "كتب\nand more", "en", ""))
	land(t, db, user, verdictOp(opID(1112), "bad", "كتب", "en", ""))
	sweep(t, db)

	got, err := db.SenseVerdicts(t.Context())
	if err != nil {
		t.Fatalf("sense verdicts: %v", err)
	}
	if want := []store.SenseVerdict{{Root: "كتب", Locale: "en", Bad: 1}}; !slices.Equal(got, want) {
		t.Fatalf("the tally came back %+v, so text a reader typed is keyed as a root", got)
	}
}

// The failure: the operator's list of reports to read is buried under
// hundreds of one-word thumbs, or the filter that clears them also drops a
// real report whose text merely starts like one.
func TestTheReportListCanLeaveOutVerdictsWithoutLosingAReport(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-report-filter")
	exec(t, pool, `INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES ('كتب', 'writing', 'écriture')`)
	land(t, db, user, verdictOp(opID(1120), "bad", "كتب", "en", ""))
	land(t, db, user, reportOp(opID(1121), "improvement", "the sense bad: it reads backwards"))
	land(t, db, user, reportOp(opID(1122), "bug", "sense bad: كتب"))
	sweep(t, db)
	exec(t, pool, `UPDATE reports SET status = 'dismissed' WHERE kind = 'bug'`)

	list, truncated, err := db.Reports(t.Context(), store.ReportFilter{ExcludeVerdicts: true})
	if err != nil {
		t.Fatalf("reports: %v", err)
	}
	if truncated || len(list) != 2 {
		t.Fatalf("leaving out verdicts kept %d reports (truncated %v), wanted the improvement and the bug", len(list), truncated)
	}
	for _, r := range list {
		if r.Kind == "improvement" && strings.HasPrefix(r.Body, "sense bad: ") {
			t.Errorf("a verdict is still on the list: %+v", r)
		}
	}

	dismissed, _, err := db.Reports(t.Context(), store.ReportFilter{Status: "dismissed"})
	if err != nil {
		t.Fatalf("reports: %v", err)
	}
	if len(dismissed) != 1 || dismissed[0].Kind != "bug" {
		t.Fatalf("the dismissed reports came back %+v", dismissed)
	}

	one, truncated, err := db.Reports(t.Context(), store.ReportFilter{Limit: 1})
	if err != nil {
		t.Fatalf("reports: %v", err)
	}
	if len(one) != 1 || !truncated {
		t.Fatalf("a list cut to one of three came back %d rows, truncated %v, so an export cannot say it is short", len(one), truncated)
	}
}

// The failure: an operator files a report while the sweep is rewriting the
// table. The sweep takes every held row out and writes it back under the same
// id; an UPDATE queued behind it under READ COMMITTED finds the old row gone
// and cannot see the new one, touches nothing, and the operator's triage is
// lost — or answered "not found" for a report that is plainly there.
func TestATriageIssuedWhileTheSweepIsRewritingTheTableStillLands(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-triage-race")
	land(t, db, user, reportOp(opID(1130), "bug", "the audio stops at the end of the set"))
	sweep(t, db)
	var id string
	if err := pool.QueryRow(t.Context(), `SELECT id::text FROM reports`).Scan(&id); err != nil {
		t.Fatalf("read the report id: %v", err)
	}

	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	defer func() { _ = tx.Rollback(t.Context()) }()
	if _, err := tx.Exec(t.Context(), store.SweepReportsSQL); err != nil {
		t.Fatalf("sweep inside a transaction: %v", err)
	}

	const issue = "https://github.com/MohammadBnei/wird/issues/1"
	done := make(chan error, 1)
	go func() { done <- db.TriageReport(t.Context(), id, "bug", "issued", issue) }()

	// The triage has to be queued on the sweep's lock before the sweep commits,
	// or this is two writes in a row rather than a race.
	deadline := time.Now().Add(5 * time.Second)
	for count(t, pool, `SELECT count(*)::int FROM pg_stat_activity
	                     WHERE datname = current_database() AND wait_event_type = 'Lock'`) == 0 {
		if time.Now().After(deadline) {
			t.Fatal("the triage never waited on the sweep, so this proves nothing")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatalf("commit the sweep: %v", err)
	}

	if err := <-done; err != nil {
		t.Fatalf("a triage behind a sweep came back %v", err)
	}
	if n := count(t, pool, `SELECT count(*)::int FROM reports
	                         WHERE status = 'issued' AND category = 'bug' AND issue_url = '`+issue+`'`); n != 1 {
		t.Fatalf("%d reports carry the triage, so it was dropped behind the sweep", n)
	}
}

// The failure: a triage of an id no report has comes back as success, and the
// operator believes a report was filed that was not.
func TestATriageAimedAtNoReportSaysSo(t *testing.T) {
	db, _ := testenv.Postgres(t)
	err := db.TriageReport(t.Context(), "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "bug", "issued", "")
	if !errors.Is(err, store.ErrReportNotFound) {
		t.Fatalf("a triage of an id no report has came back %v, not ErrReportNotFound", err)
	}
}

// The failure: the sweep rewrites every report on every tick, and a column it
// forgets is reset on the next one — the operator's triage undone within the
// interval, or the locale and sense hash dropped on the way out of the inbox
// so no verdict can be tied to the sentence it judged.
func TestTheSweepKeepsTheTriageAndWhatTheVerdictJudged(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-sweep-keeps")
	exec(t, pool, `INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES ('كتب', 'writing', 'écriture')`)
	land(t, db, user, verdictOp(opID(1140), "bad", "كتب", "fr", hashOf("écriture")))
	sweep(t, db)

	if n := count(t, pool, `SELECT count(*)::int FROM reports
	                         WHERE locale = 'fr' AND sense_hash = '`+hashOf("écriture")+`'
	                           AND status = 'new' AND category IS NULL AND issue_url IS NULL`); n != 1 {
		t.Fatalf("%d reports carry the locale, the sense hash and an untriaged status out of the inbox", n)
	}

	var id string
	if err := pool.QueryRow(t.Context(), `SELECT id::text FROM reports`).Scan(&id); err != nil {
		t.Fatalf("read the report id: %v", err)
	}
	const issue = "https://github.com/MohammadBnei/wird/issues/2"
	if err := db.TriageReport(t.Context(), id, "sense", "issued", issue); err != nil {
		t.Fatalf("triage: %v", err)
	}
	sweep(t, db)
	sweep(t, db)

	if n := count(t, pool, `SELECT count(*)::int FROM reports
	                         WHERE id = '`+id+`' AND locale = 'fr' AND sense_hash = '`+hashOf("écriture")+`'
	                           AND category = 'sense' AND status = 'issued' AND issue_url = '`+issue+`'`); n != 1 {
		t.Fatal("two sweeps later the report no longer carries its triage, locale and sense hash")
	}
}

// The failure: locale and sense_hash are the device's to set, the columns
// CHECK their length, and a CHECK violation is a permanent refusal — so one
// over-long value parks the report forever and the reader's words are lost.
// And a locale the app does not read in is kept, so the verdict tally grows a
// row per string a device invents.
func TestAnOverLongOrUnknownLocaleOrSenseHashIsBlankedNotRefused(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-report-longlocale")

	land(t, db, user, verdictOp(opID(1150), "bad", "كتب", strings.Repeat("f", 11), strings.Repeat("a", 65)))
	land(t, db, user, verdictOp(opID(1151), "bad", "كتب", "de", ""))
	land(t, db, user, verdictOp(opID(1152), "bad", "كتب", "fr", ""))

	if n := count(t, pool, `SELECT count(*)::int FROM report_inbox WHERE locale = '' AND sense_hash = ''`); n != 2 {
		t.Fatalf("%d of two inbox rows read the over-long or unknown values as 'the device did not say'", n)
	}
	if n := count(t, pool, `SELECT count(*)::int FROM report_inbox WHERE locale = 'fr'`); n != 1 {
		t.Fatal("a French locale was blanked along with the ones the app does not read in")
	}
}

// The failure: a reader types a report that happens to start like a verdict,
// and the list leaves it out as one while the tally, which finds no root in
// it, never counts it either — the words fall between the two and nobody reads
// them.
func TestATypedReportThatStartsLikeAVerdictIsStillListed(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-typed-verdict")
	exec(t, pool, `INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES ('كتب', 'writing', 'écriture')`)
	land(t, db, user, reportOp(opID(1160), "improvement", "sense bad: the French for كتب reads backwards"))
	land(t, db, user, verdictOp(opID(1161), "bad", "كتب", "en", ""))
	sweep(t, db)

	list, _, err := db.Reports(t.Context(), store.ReportFilter{ExcludeVerdicts: true})
	if err != nil {
		t.Fatalf("reports: %v", err)
	}
	if len(list) != 1 || list[0].Body != "sense bad: the French for كتب reads backwards" {
		t.Fatalf("leaving out verdicts kept %+v, where the typed report is the one that must stay", list)
	}
}

// The failure: the app and the server compute sense_hash differently — a
// normalisation, an encoding, a different slice of the hex — and every bad
// verdict reads as cast against text since corrected, so the tally never
// points at a sense that is wrong today. The Dart suite asserts this same
// constant for the same text.
func TestTheAppAndTheServerAgreeOnTheHashOfASense(t *testing.T) {
	_, pool := testenv.Postgres(t)
	const text, want = "to bind; عقل — lier", "66b51edc2622"

	var got string
	if err := pool.QueryRow(t.Context(), `SELECT `+store.SenseHashSQL("$1::text"), text).Scan(&got); err != nil {
		t.Fatalf("hash: %v", err)
	}
	if got != want {
		t.Fatalf("the server hashes %q to %s where the shared vector says %s", text, got, want)
	}
	if got := hashOf(text); got != want {
		t.Fatalf("this test's own hash of %q is %s, not %s", text, got, want)
	}
}
