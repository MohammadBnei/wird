package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

func TestASubjectSeenTwiceIsOneReaderAndNotASecondEmptyAccount(t *testing.T) {
	db, _ := testenv.Postgres(t)

	first, err := db.EnsureUser(t.Context(), "sub-abc")
	if err != nil {
		t.Fatalf("first sight: %v", err)
	}
	second, err := db.EnsureUser(t.Context(), "sub-abc")
	if err != nil {
		t.Fatalf("second sight: %v", err)
	}
	if first.ID != second.ID {
		t.Fatalf("the same subject got two readers: %s then %s", first.ID, second.ID)
	}

	other, err := db.EnsureUser(t.Context(), "sub-xyz")
	if err != nil {
		t.Fatalf("another subject: %v", err)
	}
	if other.ID == first.ID {
		t.Fatal("two subjects share one reader, so each would read the other's progress")
	}
}

func TestAReplayedOpIsRecordedOnceSoAPrayerIsNeverCountedTwice(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-replay")
	other := reader(t, db, "sub-other")
	const op = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"

	applied, err := db.RecordOp(t.Context(), user, op)
	if err != nil || !applied {
		t.Fatalf("first flush did not apply: applied=%v err=%v", applied, err)
	}
	applied, err = db.RecordOp(t.Context(), user, op)
	if err != nil {
		t.Fatalf("replayed flush: %v", err)
	}
	if applied {
		t.Fatal("a replayed op applied a second time, which is a prayer counted twice")
	}

	// The log is scoped per reader: two devices minting the same id must not
	// silence each other's write.
	applied, err = db.RecordOp(t.Context(), other, op)
	if err != nil || !applied {
		t.Fatalf("another reader's op was swallowed: applied=%v err=%v", applied, err)
	}
}

func TestOpsPastTheReplayWindowArePrunedSoTheLogCannotGrowForever(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-prune")

	exec(t, pool, `INSERT INTO op_log (user_id, client_op_id, applied_at)
	               VALUES ($1, gen_random_uuid(), now() - $2::interval),
	                      ($1, gen_random_uuid(), now() - interval '1 day')`,
		user, "91 days")

	if _, err := db.PruneOpLog(t.Context()); err != nil {
		t.Fatalf("prune: %v", err)
	}
	if left := count(t, pool, `SELECT count(*) FROM op_log`); left != 1 {
		t.Fatalf("expected only the op still inside the window to survive, %d rows left", left)
	}
}

func TestProgressShowsNoRatioUntilTheReaderHasStudiedTheirFirstSet(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-new")

	p, err := db.Progress(t.Context(), user)
	if err != nil {
		t.Fatalf("progress: %v", err)
	}
	if p.PrayersPerSet != nil {
		t.Fatalf("a new reader was given a ratio of %v instead of an em dash", *p.PrayersPerSet)
	}
	if p.Understood != 0 || p.Percent != 0 {
		t.Fatalf("a new reader has read something: %+v", p)
	}
	if len(p.RootsKnown) != 0 {
		t.Fatalf("a new reader knows roots: %v", p.RootsKnown)
	}
}

func TestProgressCountsAnAyaInTheJuzItBelongsTo(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-juz")

	cases := []struct {
		aya string
		id  int
		juz int
	}{
		{"1:1, the first aya of juz 1", 1001, 1},
		{"2:141, the last aya of juz 1", 2141, 1},
		{"2:142, the first aya of juz 2", 2142, 2},
		{"78:1, the first aya of juz 30", 78001, 30},
		{"114:6, the last aya of the Qur'an", 114006, 30},
	}
	for _, c := range cases {
		exec(t, pool, `INSERT INTO ayah_understood (id, user_id, ayah_id)
		               VALUES (gen_random_uuid(), $1, $2)`, user, c.id)
	}

	p, err := db.Progress(t.Context(), user)
	if err != nil {
		t.Fatalf("progress: %v", err)
	}
	for _, c := range cases {
		if p.JuzUnderstood[c.juz-1] == 0 {
			t.Errorf("%s was not counted in juz %d: %v", c.aya, c.juz, p.JuzUnderstood)
		}
	}
	if p.Understood != len(cases) {
		t.Errorf("understood %d ayas, expected %d", p.Understood, len(cases))
	}
	if want := float64(len(cases)) / store.AyasInTheQuran; p.Percent != want {
		t.Errorf("percent %v, expected %v", p.Percent, want)
	}
}

func TestOneReadersProgressNeverCountsAnothersPrayers(t *testing.T) {
	db, pool := testenv.Postgres(t)
	mine := reader(t, db, "sub-mine")
	theirs := reader(t, db, "sub-theirs")

	for _, user := range []string{mine, theirs} {
		exec(t, pool, `INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order)
		               VALUES (gen_random_uuid(), $1, 1, 96001, 96005, 'nuzul')`, user)
		exec(t, pool, `INSERT INTO set_prayers (id, set_id, user_id, prayer_name)
		               SELECT gen_random_uuid(), id, $1, 'fajr' FROM sets WHERE user_id = $1`, user)
	}
	exec(t, pool, `INSERT INTO ayah_understood (id, user_id, ayah_id)
	               VALUES (gen_random_uuid(), $1, 96001)`, theirs)

	p, err := db.Progress(t.Context(), mine)
	if err != nil {
		t.Fatalf("progress: %v", err)
	}
	if p.Sets != 1 || p.Prayers != 1 {
		t.Fatalf("counted another reader's rows: %d sets, %d prayers", p.Sets, p.Prayers)
	}
	if p.Understood != 0 {
		t.Fatalf("another reader's understood aya showed up: %d", p.Understood)
	}
	if p.PrayersPerSet == nil || *p.PrayersPerSet != 1 {
		t.Fatalf("ratio %v, expected 1", p.PrayersPerSet)
	}
}

func TestAKeptItemDeletedOnThePhoneStaysOffTheListOnTheTablet(t *testing.T) {
	db, pool := testenv.Postgres(t)
	user := reader(t, db, "sub-kept")
	other := reader(t, db, "sub-kept-other")

	keep(t, pool, user, "note", "a note kept and then forgotten", true)
	keep(t, pool, user, "note", "a note the reader still has", false)
	keep(t, pool, user, "aya", "an aya to come back to", false)
	keep(t, pool, other, "note", "somebody else's note", false)

	all, err := db.Kept(t.Context(), user, "")
	if err != nil {
		t.Fatalf("kept: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("expected the two live items, got %d: %+v", len(all), all)
	}
	for _, item := range all {
		if item.Body == "a note kept and then forgotten" {
			t.Fatal("a tombstoned item came back, which is a deletion the other device undoes")
		}
		if item.Body == "somebody else's note" {
			t.Fatal("another reader's kept item is on this list")
		}
	}

	notes, err := db.Kept(t.Context(), user, "note")
	if err != nil {
		t.Fatalf("kept notes: %v", err)
	}
	if len(notes) != 1 || notes[0].Kind != "note" {
		t.Fatalf("the note filter answered with %+v", notes)
	}
	if len(notes[0].Tags) != 1 || notes[0].Tags[0] != "revisit" {
		t.Fatalf("the reader's tags did not survive the round trip: %v", notes[0].Tags)
	}
}

func TestProseNobodyHasLicensedYetIsMissingRatherThanInvented(t *testing.T) {
	db, _ := testenv.Postgres(t)

	unseeded := []struct {
		what string
		read func() error
	}{
		{"tafsir for 2:255", func() error { _, err := db.Tafsir(t.Context(), 2255); return err }},
		{"iʿrāb for 2:255", func() error { _, err := db.Irab(t.Context(), 2255); return err }},
		{"the lexicon for ك ت ب", func() error { _, err := db.Lexicon(t.Context(), "كتب"); return err }},
	}
	for _, c := range unseeded {
		if err := c.read(); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("%s answered with %v; an unsourced aya must say nothing at all", c.what, err)
		}
	}
}

func TestSeededProseSaysInThePayloadThatItIsAPlaceholder(t *testing.T) {
	db, _ := testenv.Postgres(t)

	lexicon, err := db.Lexicon(t.Context(), "صبر")
	if err != nil {
		t.Fatalf("lexicon: %v", err)
	}
	for _, e := range lexicon {
		if !e.Placeholder {
			t.Errorf("%q reads as sourced scholarship, which it is not", e.Source)
		}
	}

	tafsir, err := db.Tafsir(t.Context(), 103003)
	if err != nil {
		t.Fatalf("tafsir: %v", err)
	}
	for _, e := range tafsir {
		if !e.Placeholder {
			t.Errorf("tafsir attributed to %q reads as sourced, which it is not", e.Author)
		}
	}

	irab, err := db.Irab(t.Context(), 103003)
	if err != nil {
		t.Fatalf("irab: %v", err)
	}
	for _, e := range irab {
		if !e.Placeholder {
			t.Errorf("the parsing of %q reads as sourced, which it is not", e.SegmentAr)
		}
	}
}

func reader(t *testing.T, db *store.Store, subject string) string {
	t.Helper()
	user, err := db.EnsureUser(t.Context(), subject)
	if err != nil {
		t.Fatalf("mint reader %s: %v", subject, err)
	}
	return user.ID
}

func keep(t *testing.T, pool *pgxpool.Pool, user, kind, body string, deleted bool) {
	t.Helper()
	var at *time.Time
	if deleted {
		now := time.Now()
		at = &now
	}
	exec(t, pool, `INSERT INTO kept_items (id, user_id, kind, body, tags, created_at, updated_at, deleted_at)
	               VALUES (gen_random_uuid(), $1, $2, $3, ARRAY['revisit'], now(), now(), $4)`,
		user, kind, body, at)
}

func exec(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	if _, err := pool.Exec(t.Context(), sql, args...); err != nil {
		t.Fatalf("seed: %v", err)
	}
}

func count(t *testing.T, pool *pgxpool.Pool, sql string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(t.Context(), sql).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	return n
}
