package store

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// Sense is one root's reading, as the route serves it and as the seeder writes
// it. One struct for both directions so the wire shape and the row shape cannot
// drift apart.
//
// The poetic register is carried here because the seeder reads it out of the
// drafting log and the column stores it, and it is `json:"-"` because it is
// never served: the app has no widget for it and
// jidhr/pkg/root/meaning_test.go fails any corpus that carries one. A tag is a
// cheaper gate than a memory — nothing has to remember to leave it out of a
// response body, because it structurally cannot get into one.
type Sense struct {
	Root     string `json:"root"`
	En       string `json:"en"`
	Fr       string `json:"fr"`
	PoeticEn string `json:"-"`
	PoeticFr string `json:"-"`
}

// SensePack is the whole served body's data half: the rows, and the version
// they hash to. The prose around them — source, attribution, basis — is not
// here and is not in the database either. It lives as constants beside the
// handler, because a single-row table nobody updates is exactly the corpus_meta
// defect ADR 0010 exists to stop repeating.
type SensePack struct {
	Version string
	Senses  []Sense
}

// sensesVersionSQL hashes the served content, and only the served content: the
// roots, the English and the French, in one order, in one string.
//
// It is a content hash rather than a count and a max(updated_at), and both
// halves of that were measured rather than argued. updated_at has DEFAULT now()
// and no trigger, so a plain UPDATE of a sense — which is precisely "a
// correction reaches readers in minutes", the whole payoff of ADR 0010 — moves
// no timestamp at all: same version, same ETag, 304, and no phone ever learns
// the correction. And the seeder's DELETE-then-insert restamps every row, so
// every re-seed, including one that changes nothing, would re-download 805 KB
// to every device. A hash is wrong in neither direction.
//
// COALESCE because string_agg over no rows is NULL, and md5(NULL) is NULL,
// which would fail the scan. An empty table hashes the empty string, which is a
// real version for a real state: nothing is seeded yet.
//
// The poetic columns are absent on purpose. A register that is never served
// must not move the version a phone compares, or every device re-downloads the
// pack over prose it will never see.
//
// COLLATE "C" is load-bearing, and this was measured too: the same rows hash
// 5ca334668aff2198b96ef13e494cc12a under en_US.utf8 and ff432e09f4d8c05c8f11be679e43c46d
// under C. Without it the digest is whatever the database's LC_COLLATE says, so
// a glibc or ICU bump in a base image, a pg_upgrade, or a restore into a
// differently-created database moves every phone's ETag with no data change and
// nothing to tell an operator why. It also makes the hash comparable between a
// laptop and production, which is what lets senseseed print a version worth
// checking the route against. The body below sorts the same way for the same
// reason: the ETag has to label the bytes it is served with.
const sensesVersionSQL = `
	SELECT md5(COALESCE(string_agg(
	         root_letters || E'\x1f' || sense_en || E'\x1f' || sense_fr,
	         E'\x1e' ORDER BY root_letters COLLATE "C"), ''))
	  FROM root_senses`

// SensesVersion is what HEAD /v1/senses answers with. The check has to be
// cheap, because the app makes it on every foreground and the body behind it is
// 805 KB: this reads no rows and marshals nothing.
func (s *Store) SensesVersion(ctx context.Context) (string, error) {
	var digest string
	err := s.pool.QueryRow(ctx, sensesVersionSQL).Scan(&digest)
	return digest, err
}

// Senses reads the pack and the version of exactly those rows.
//
// The two statements run in one read-only repeatable-read snapshot, which is
// the only part of this that is not obvious. Read them separately and a re-seed
// committing in between hands a phone one version's bytes under the other
// version's ETag — after which the phone's next HEAD matches, answers 304, and
// it keeps the wrong prose under the right version forever. A snapshot costs a
// transaction on a route fetched at most once per foreground.
//
// It never answers ErrNotFound, and that is a deliberate break from Lexicon's
// convention a few functions up. Lexicon is per-root, where an absent row is a
// miss and 404 is the truth. This is the whole body, where absence is a fact:
// "no senses are seeded here" is true, actionable, and something a client must
// be able to apply without treating the server as broken.
func (s *Store) Senses(ctx context.Context) (SensePack, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.RepeatableRead,
		AccessMode: pgx.ReadOnly,
	})
	if err != nil {
		return SensePack{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	pack := SensePack{Senses: []Sense{}}
	if err := tx.QueryRow(ctx, sensesVersionSQL).Scan(&pack.Version); err != nil {
		return SensePack{}, err
	}

	rows, err := tx.Query(ctx,
		`SELECT root_letters, sense_en, sense_fr FROM root_senses ORDER BY root_letters COLLATE "C"`)
	if err != nil {
		return SensePack{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var sn Sense
		if err := rows.Scan(&sn.Root, &sn.En, &sn.Fr); err != nil {
			return SensePack{}, err
		}
		pack.Senses = append(pack.Senses, sn)
	}
	return pack, rows.Err()
}

// ReplaceSenses writes the whole pack in one transaction: what is here
// afterwards is what was handed in, and nothing else.
//
// The DELETE is the point of the word "replace". A root the drafting log has
// stopped carrying has to leave, and an upsert-only seed would keep answering
// with a sense nobody stands behind any more.
//
// ponytail: one INSERT per row rather than one statement over arrays. It is not
// a style choice — a multi-row INSERT with ON CONFLICT DO UPDATE refuses to
// touch the same key twice ("cannot affect row a second time"), and 553 of the
// 1,642 roots carry more than one row in the log, so the array version dies on
// the 554th. Insert in the order the caller hands them over and the last row
// for a root wins, which is the log's own rule with no selection code in it.
// 2,306 round trips inside one transaction is a seed, not a request path; batch
// it if a seed ever has to be fast.
func (s *Store) ReplaceSenses(ctx context.Context, senses []Sense) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `DELETE FROM root_senses`); err != nil {
		return err
	}
	for _, sn := range senses {
		// NULLIF: an unwritten poetic register is absent, never blank — the
		// same distinction jidhrcorpus makes when it exports meanings.
		if _, err := tx.Exec(ctx, `
			INSERT INTO root_senses (root_letters, sense_en, sense_fr, poetic_en, poetic_fr)
			VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''))
			ON CONFLICT (root_letters) DO UPDATE
			   SET sense_en = EXCLUDED.sense_en, sense_fr = EXCLUDED.sense_fr,
			       poetic_en = EXCLUDED.poetic_en, poetic_fr = EXCLUDED.poetic_fr,
			       updated_at = now()`,
			sn.Root, sn.En, sn.Fr, sn.PoeticEn, sn.PoeticFr); err != nil {
			return fmt.Errorf("root %s: %w", sn.Root, err)
		}
	}
	return tx.Commit(ctx)
}
