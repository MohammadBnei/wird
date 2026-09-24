package store

import (
	"context"
	"time"
)

// What an operator is allowed to know. Wird knows which ayas a person
// understood, what they wrote in their notes and when they prayed, so a
// dashboard over it is surveillance of somebody's practice unless it is built
// not to be. What is here is counts, and the reports people chose to send.
//
// Nothing in this file takes a reader. A statement that could be narrowed to
// one — a placeholder to bind an id to, or a user_id to compare — is what the
// rule forbids, and adminAggregates below is how a test can say so rather than
// this comment being the only thing that does.

const (
	readersSQL      = `SELECT count(*) FROM users`
	setsPrayedSQL   = `SELECT count(*) FROM set_prayers`
	syncFailuresSQL = `SELECT coalesce(sum(ops), 0)::bigint FROM sync_outcomes WHERE status = 'failed'`
	parkedWritesSQL = `SELECT coalesce(sum(ops), 0)::bigint FROM sync_outcomes WHERE status = 'refused'`

	// The only place a device says what it has bundled, which is why a report
	// carries the version at all: a bug can then be tied to a build.
	corpusVersionsSQL = `SELECT corpus_version, count(*) FROM reports
	                      GROUP BY corpus_version ORDER BY corpus_version`
)

// adminAggregates is every statement the dashboard can cause to run. A new one
// has to be added here to be run at all, which is what lets one test hold them
// all to the same rule.
var adminAggregates = []string{
	readersSQL, setsPrayedSQL, syncFailuresSQL, parkedWritesSQL, corpusVersionsSQL,
}

// A count each, and one distribution. ParkedWrites is the writes the server
// refused, which a device parks the moment it hears; SyncFailures is the ones
// it answered "failed", which a device retries and parks only when its budget
// runs out. Neither number can say whose write it was.
type Health struct {
	Readers        int64          `json:"readers"`
	SetsPrayed     int64          `json:"sets_prayed"`
	SyncFailures   int64          `json:"sync_failures"`
	ParkedWrites   int64          `json:"parked_writes"`
	CorpusVersions []FieldVersion `json:"corpus_versions"`
}

type FieldVersion struct {
	CorpusVersion int   `json:"corpus_version"`
	Reports       int64 `json:"reports"`
}

// ponytail: four round trips and a scan for one page. Fold them into one
// statement if the dashboard ever refreshes on a timer.
func (s *Store) Health(ctx context.Context) (Health, error) {
	h := Health{CorpusVersions: []FieldVersion{}}
	for sql, into := range map[string]*int64{
		readersSQL:      &h.Readers,
		setsPrayedSQL:   &h.SetsPrayed,
		syncFailuresSQL: &h.SyncFailures,
		parkedWritesSQL: &h.ParkedWrites,
	} {
		if err := s.pool.QueryRow(ctx, sql).Scan(into); err != nil {
			return h, err
		}
	}

	rows, err := s.pool.Query(ctx, corpusVersionsSQL)
	if err != nil {
		return h, err
	}
	defer rows.Close()
	for rows.Next() {
		var v FieldVersion
		if err := rows.Scan(&v.CorpusVersion, &v.Reports); err != nil {
			return h, err
		}
		h.CorpusVersions = append(h.CorpusVersions, v)
	}
	return h, rows.Err()
}

// A Report is what somebody chose to send, and all of it. There is no reader on
// it: the table has no column for one, and the id is the server's own rather
// than the op id, which op_log holds against the reader who sent it.
type Report struct {
	ID            string    `json:"id"`
	Kind          string    `json:"kind"`
	Body          string    `json:"body"`
	AppVersion    string    `json:"app_version"`
	Platform      string    `json:"platform"`
	Screen        string    `json:"screen"`
	CorpusVersion int       `json:"corpus_version"`
	CreatedAt     time.Time `json:"created_at"`
}

// ReportPage is how many reports one list carries.
const ReportPage = 200

// Reports, newest first. Reports are one-way: this is the only place they are
// read, and nothing the operator does here travels back to a device.
func (s *Store) Reports(ctx context.Context, limit int) ([]Report, error) {
	if limit <= 0 || limit > ReportPage {
		limit = ReportPage
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, kind, body, app_version, platform, screen, corpus_version, created_at
		  FROM reports ORDER BY created_at DESC, id LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []Report{}
	for rows.Next() {
		var r Report
		if err := rows.Scan(&r.ID, &r.Kind, &r.Body, &r.AppVersion, &r.Platform,
			&r.Screen, &r.CorpusVersion, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
