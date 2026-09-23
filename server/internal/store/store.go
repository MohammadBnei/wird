// Package store holds every SQL statement the API runs. Handlers stay thin and
// the database shape lives in one place.
package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"github.com/MohammadBnei/wird/server/migrations"
)

// ErrNotFound is what an unseeded aya or root answers with. It never carries a
// reason: what the caller gets is a 404, not the shape of our tables.
var ErrNotFound = errors.New("not found")

type Store struct{ pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Open connects and brings the schema up to date. The server and the test
// database take the same path, so a migration that only works in one of them
// cannot exist.
func Open(ctx context.Context, url string) (*Store, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	if err := Migrate(ctx, url); err != nil {
		pool.Close()
		return nil, err
	}
	return New(pool), nil
}

func (s *Store) Close() { s.pool.Close() }

// Migrate runs the goose migrations embedded from server/migrations.
func Migrate(ctx context.Context, url string) error {
	db := stdlib.OpenDB(*mustParse(url))
	defer db.Close()
	goose.SetBaseFS(migrations.FS)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.UpContext(ctx, db, ".")
}

func mustParse(url string) *pgx.ConnConfig {
	cfg, err := pgx.ParseConfig(url)
	if err != nil {
		panic(fmt.Sprintf("store: unusable database url: %v", err))
	}
	return cfg
}

type User struct {
	ID          string    `json:"id"`
	OIDCSubject string    `json:"oidc_subject"`
	CreatedAt   time.Time `json:"created_at"`
}

// EnsureUser returns the reader behind a verified subject, minting the row the
// first time that subject is seen. The caller has already verified the token:
// a subject that reaches here from an unverified one is a stolen account.
func (s *Store) EnsureUser(ctx context.Context, subject string) (User, error) {
	var u User
	err := s.pool.QueryRow(ctx, `
		INSERT INTO users (id, oidc_subject) VALUES (gen_random_uuid(), $1)
		ON CONFLICT (oidc_subject) DO UPDATE SET oidc_subject = EXCLUDED.oidc_subject
		RETURNING id, oidc_subject, created_at`, subject).
		Scan(&u.ID, &u.OIDCSubject, &u.CreatedAt)
	return u, err
}

type CorpusVersion struct {
	CorpusVersion int       `json:"corpus_version"`
	BuiltAt       time.Time `json:"built_at"`
}

func (s *Store) CorpusVersion(ctx context.Context) (CorpusVersion, error) {
	var c CorpusVersion
	err := s.pool.QueryRow(ctx,
		`SELECT corpus_version, built_at FROM corpus_meta WHERE id = 1`).
		Scan(&c.CorpusVersion, &c.BuiltAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return c, ErrNotFound
	}
	return c, err
}

// AyasInTheQuran is the Ḥafṣ count, the same assumption screen 1d states.
const AyasInTheQuran = 6236

// Where each juz starts, as an ayah id. The corpus is on the device, so the
// server buckets by the boundaries themselves — the thirty printed in every
// Ḥafṣ muṣḥaf, which is why they can be a constant rather than a join.
var juzStarts = [30]int{
	1001, 2142, 2253, 3092, 4024, 4148, 5082, 6111, 7088, 8041,
	9093, 11006, 12053, 15001, 17001, 18075, 21001, 23001, 25021, 27056,
	29046, 33031, 36028, 39032, 41047, 46001, 51031, 58001, 67001, 78001,
}

// Progress is the user-state half of screen 1d. The per-sūra rows and the
// roots' spelled display forms are not here: both need the corpus, which the
// second device already has bundled, and shipping a copy over the wire would
// put the network on a path the plan declared instant.
type Progress struct {
	Understood    int      `json:"understood"`
	Sets          int      `json:"sets"`
	Prayers       int      `json:"prayers"`
	PrayersPerSet *float64 `json:"prayers_per_set"`
	Percent       float64  `json:"percent"`
	RootsKnown    []string `json:"roots_known"`
	JuzUnderstood [30]int  `json:"juz_understood"`
}

func (s *Store) Progress(ctx context.Context, userID string) (Progress, error) {
	p := Progress{RootsKnown: []string{}}

	rows, err := s.pool.Query(ctx,
		`SELECT ayah_id FROM ayah_understood WHERE user_id = $1`, userID)
	if err != nil {
		return p, err
	}
	for rows.Next() {
		var ayahID int
		if err := rows.Scan(&ayahID); err != nil {
			return p, err
		}
		p.Understood++
		p.JuzUnderstood[juzOf(ayahID)-1]++
	}
	if err := rows.Err(); err != nil {
		return p, err
	}

	if err := s.pool.QueryRow(ctx, `
		SELECT (SELECT count(*) FROM sets WHERE user_id = $1),
		       (SELECT count(*) FROM set_prayers WHERE user_id = $1)`, userID).
		Scan(&p.Sets, &p.Prayers); err != nil {
		return p, err
	}

	roots, err := s.pool.Query(ctx,
		`SELECT root_letters FROM root_known WHERE user_id = $1 ORDER BY learned_at DESC`, userID)
	if err != nil {
		return p, err
	}
	for roots.Next() {
		var letters string
		if err := roots.Scan(&letters); err != nil {
			return p, err
		}
		p.RootsKnown = append(p.RootsKnown, letters)
	}
	if err := roots.Err(); err != nil {
		return p, err
	}

	p.Percent = float64(p.Understood) / AyasInTheQuran
	// A reader who has prayed no set gets no ratio at all. The screen renders
	// an em dash; a zero here would be a division by zero dressed as progress.
	if p.Sets > 0 {
		ratio := float64(p.Prayers) / float64(p.Sets)
		p.PrayersPerSet = &ratio
	}
	return p, nil
}

func juzOf(ayahID int) int {
	juz := 1
	for i := 1; i < len(juzStarts); i++ {
		if ayahID >= juzStarts[i] {
			juz = i + 1
		}
	}
	return juz
}

type KeptItem struct {
	ID          string    `json:"id"`
	Kind        string    `json:"kind"`
	AyahID      *int      `json:"ayah_id"`
	RootLetters *string   `json:"root_letters"`
	Body        string    `json:"body"`
	Tags        []string  `json:"tags"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Kept is a read model. Writes go through the outbox, never through here.
// A tombstoned item is gone from the list and stays gone.
func (s *Store) Kept(ctx context.Context, userID, kind string) ([]KeptItem, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, kind, ayah_id, root_letters, body, tags, created_at, updated_at
		  FROM kept_items
		 WHERE user_id = $1 AND deleted_at IS NULL AND ($2 = '' OR kind = $2)
		 ORDER BY created_at DESC`, userID, kind)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []KeptItem{}
	for rows.Next() {
		var it KeptItem
		if err := rows.Scan(&it.ID, &it.Kind, &it.AyahID, &it.RootLetters,
			&it.Body, &it.Tags, &it.CreatedAt, &it.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, it)
	}
	return items, rows.Err()
}

type TafsirEntry struct {
	Author      string  `json:"author"`
	DeathNote   *string `json:"death_note"`
	Body        string  `json:"body"`
	Placeholder bool    `json:"placeholder"`
}

func (s *Store) Tafsir(ctx context.Context, ayahID int) ([]TafsirEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT author, death_note, body, is_placeholder
		  FROM tafsir_entries WHERE ayah_id = $1 ORDER BY author`, ayahID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []TafsirEntry
	for rows.Next() {
		var e TafsirEntry
		if err := rows.Scan(&e.Author, &e.DeathNote, &e.Body, &e.Placeholder); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, ErrNotFound
	}
	return out, nil
}

type IrabEntry struct {
	Position    int    `json:"position"`
	SegmentAr   string `json:"segment_ar"`
	Note        string `json:"note"`
	Placeholder bool   `json:"placeholder"`
}

func (s *Store) Irab(ctx context.Context, ayahID int) ([]IrabEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT position, segment_ar, note, is_placeholder
		  FROM irab_entries WHERE ayah_id = $1 ORDER BY position`, ayahID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []IrabEntry
	for rows.Next() {
		var e IrabEntry
		if err := rows.Scan(&e.Position, &e.SegmentAr, &e.Note, &e.Placeholder); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, ErrNotFound
	}
	return out, nil
}

type LexiconEntry struct {
	Source      string `json:"source"`
	Body        string `json:"body"`
	Placeholder bool   `json:"placeholder"`
}

func (s *Store) Lexicon(ctx context.Context, letters string) ([]LexiconEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT source, body, is_placeholder
		  FROM lexicon_entries WHERE root_letters = $1 ORDER BY source`, letters)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []LexiconEntry
	for rows.Next() {
		var e LexiconEntry
		if err := rows.Scan(&e.Source, &e.Body, &e.Placeholder); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, ErrNotFound
	}
	return out, nil
}

// RecordOp writes an op id down and says whether this call is the one that did
// it. A replay lands on the same primary key and answers false, which is what
// stops a flush counting a prayer twice.
func (s *Store) RecordOp(ctx context.Context, userID, clientOpID string) (bool, error) {
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO op_log (user_id, client_op_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING`, userID, clientOpID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// OpLogWindow is how long a replayed flush is still recognised as a replay.
const OpLogWindow = 90 * 24 * time.Hour

// PruneOpLog drops ops past the window. Without it the one table that grows
// with every write a reader ever makes never stops growing.
func (s *Store) PruneOpLog(ctx context.Context) (int64, error) {
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM op_log WHERE applied_at < now() - $1::interval`,
		fmt.Sprintf("%d hours", int(OpLogWindow.Hours())))
	return tag.RowsAffected(), err
}
