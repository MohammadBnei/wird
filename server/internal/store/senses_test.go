package store_test

import (
	"errors"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

func drafts() []store.Sense {
	return []store.Sense{
		{Root: "رحم", En: "to show mercy; the womb", Fr: "faire miséricorde ; la matrice",
			PoeticEn: "the womb and the mercy are one word", PoeticFr: "la matrice et la miséricorde"},
		{Root: "صبر", En: "to bind oneself; to endure", Fr: "se lier ; endurer"},
	}
}

func versionOf(t *testing.T, db *store.Store) string {
	t.Helper()
	v, err := db.SensesVersion(t.Context())
	if err != nil {
		t.Fatalf("read the pack version: %v", err)
	}
	return v
}

// The failure this whole version scheme exists for, and it was measured rather
// than argued. updated_at has DEFAULT now() and no trigger, so under a count
// plus max(updated_at) a plain `UPDATE root_senses SET sense_en = …` — which IS
// "a correction reaches readers in minutes", the entire payoff of ADR 0010 —
// moves nothing: same version, same ETag, 304, and not one phone ever learns
// the correction. Silent, and indistinguishable from a healthy no-op.
//
// The second half is the other direction: a re-seed that changes nothing must
// not change the version either, or every re-seed re-downloads 805 KB to every
// device — which is what DELETE-then-insert restamping every row would do.
func TestACorrectedSenseShipsAsA304NoPhoneEverLearnsFrom(t *testing.T) {
	db, pool := testenv.Postgres(t)

	if err := db.ReplaceSenses(t.Context(), drafts()); err != nil {
		t.Fatalf("seed: %v", err)
	}
	seeded := versionOf(t, db)

	if err := db.ReplaceSenses(t.Context(), drafts()); err != nil {
		t.Fatalf("re-seed: %v", err)
	}
	if again := versionOf(t, db); again != seeded {
		t.Errorf("a re-seed of the same senses moved the version from %q to %q, so every device "+
			"re-downloads the whole pack over nothing", seeded, again)
	}

	if _, err := pool.Exec(t.Context(),
		`UPDATE root_senses SET sense_en = 'to show mercy' WHERE root_letters = 'رحم'`); err != nil {
		t.Fatalf("correct a sense: %v", err)
	}
	if corrected := versionOf(t, db); corrected == seeded {
		t.Fatalf("a corrected sense still hashes to %q, so the ETag matches, the answer is 304 "+
			"and the correction reaches nobody", corrected)
	}
}

// The failure: the route 404s, or errors, when nothing is seeded — and a fresh
// environment, or a laptop build pointed at an unseeded database, reads as
// broken rather than as empty. "No senses are seeded here" is a true and
// actionable answer, so it is a pack with no rows and not an ErrNotFound, which
// is a deliberate break from the convention Lexicon a few functions up keeps.
func TestAnUnseededDatabaseAnswersAsThoughTheRouteWereMissing(t *testing.T) {
	db, _ := testenv.Postgres(t)

	pack, err := db.Senses(t.Context())
	if err != nil {
		t.Fatalf("an empty table answered %v, and errors.Is(ErrNotFound) is %v", err, errors.Is(err, store.ErrNotFound))
	}
	if pack.Senses == nil {
		t.Error("the senses are nil, which marshals as null rather than as []")
	}
	if len(pack.Senses) != 0 {
		t.Errorf("%d senses out of an empty table", len(pack.Senses))
	}
	if pack.Version == "" {
		t.Error("an empty pack has no version, so a phone cannot tell one empty answer from another")
	}
}

// The failure: the seeder dies on the 554th root. 553 of the 1,642 carry more
// than one row in the drafting log, whose own rule is that the last row for a
// root wins — so the primary key IS that rule, applied in the order the rows
// were read. A multi-row INSERT cannot do it (ON CONFLICT DO UPDATE refuses to
// touch the same key twice), and neither can an upsert without a DELETE: a root
// the log has stopped carrying has to leave, or the route keeps answering with a
// sense nobody stands behind.
func TestTheSecondRowForARootIsTheOneKeptAndADroppedRootLingers(t *testing.T) {
	db, pool := testenv.Postgres(t)

	if err := db.ReplaceSenses(t.Context(), []store.Sense{
		{Root: "رحم", En: "first draft", Fr: "premier jet"},
		{Root: "صبر", En: "to endure", Fr: "endurer"},
		{Root: "رحم", En: "to show mercy; the womb", Fr: "faire miséricorde ; la matrice"},
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	pack, err := db.Senses(t.Context())
	if err != nil {
		t.Fatalf("read the pack: %v", err)
	}
	if len(pack.Senses) != 2 {
		t.Fatalf("three rows for two roots became %d senses", len(pack.Senses))
	}
	for _, sn := range pack.Senses {
		if sn.Root == "رحم" && sn.En != "to show mercy; the womb" {
			t.Errorf("the root kept %q, which is the row the log superseded", sn.En)
		}
	}

	if err := db.ReplaceSenses(t.Context(), []store.Sense{
		{Root: "رحم", En: "to show mercy; the womb", Fr: "faire miséricorde ; la matrice"},
	}); err != nil {
		t.Fatalf("re-seed without صبر: %v", err)
	}
	if n := count(t, pool, `SELECT count(*) FROM root_senses WHERE root_letters = 'صبر'`); n != 0 {
		t.Errorf("a root the log stopped carrying is still served, %d row(s)", n)
	}
}

// The failure: the poetic register reaches a reader. 1,642 model calls produced
// it, this table is the only thing that holds it, and it is gated separately
// with its own battery still to write — so it is stored and never served. The
// struct tag is the gate: nothing has to remember to leave it out of a body.
func TestThePoeticRegisterIsServedBesideTheSense(t *testing.T) {
	db, pool := testenv.Postgres(t)

	if err := db.ReplaceSenses(t.Context(), drafts()); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if n := count(t, pool, `SELECT count(*) FROM root_senses WHERE poetic_en IS NOT NULL`); n != 1 {
		t.Errorf("%d rows kept a poetic register out of the one that was handed over", n)
	}
	// An unwritten register is absent, never blank.
	if n := count(t, pool, `SELECT count(*) FROM root_senses WHERE poetic_en = ''`); n != 0 {
		t.Errorf("%d rows hold a blank register, which reads as a register nobody wrote", n)
	}

	pack, err := db.Senses(t.Context())
	if err != nil {
		t.Fatalf("read the pack: %v", err)
	}
	for _, sn := range pack.Senses {
		if sn.PoeticEn != "" || sn.PoeticFr != "" {
			t.Errorf("%s came back carrying its poetic register", sn.Root)
		}
	}
}
