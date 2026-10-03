package store

import (
	"context"
	"errors"
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
	readersSQL, setsPrayedSQL, syncFailuresSQL, parkedWritesSQL, corpusVersionsSQL, senseVerdictsSQL,
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

// A Report is what somebody chose to send, and all of it. There is no reader
// on it, and applyReport and SweepReports are where the reasons for that are
// written down: the table has no column for one, and every row in it was
// written by a sweep on a clock rather than at the moment its author was
// talking to the database, so the id, the transaction id and the place on disk
// all came from the sweep. WrittenOn is a date, so there is no time of day to
// hand back either.
type Report struct {
	ID            string `json:"id"`
	Kind          string `json:"kind"`
	Body          string `json:"body"`
	AppVersion    string `json:"app_version"`
	Platform      string `json:"platform"`
	Screen        string `json:"screen"`
	CorpusVersion int    `json:"corpus_version"`
	// Which pack of senses was on the phone. corpus_version cannot say it: the
	// senses arrive over HTTP now, so two readers on one bundle can judge two
	// different sentences. Empty is a device that did not say — every report
	// written before the app learned to, and every report that is not a verdict.
	SenseVersion string `json:"sense_version"`
	// The language the reader saw, and the first twelve hex characters of the
	// sha256 of the sense text they judged. Both name something everybody in
	// that language was shown, not somebody. '' is a device that did not say.
	Locale    string `json:"locale"`
	SenseHash string `json:"sense_hash"`
	// What the operator made of it. These are the operator's words, written by
	// TriageReport, and nothing in them travels back to a device. Category and
	// IssueURL are '' until somebody sets them; Status starts at "new".
	Category  string    `json:"category"`
	Status    string    `json:"status"`
	IssueURL  string    `json:"issue_url"`
	WrittenOn time.Time `json:"written_on"`
}

// ReportPage is how many reports one list on the dashboard carries.
const ReportPage = 200

// ReportExport is how many reports one export carries.
//
// ponytail: one capped read, and the answer says when the cap cut it short.
// Page with a (written_on, id) cursor once an export comes back truncated.
const ReportExport = 5000

// The categories an operator can file a report under, and what can become of
// one. They are the column CHECKs in migration 00011, repeated so a caller can
// refuse a bad value before it reaches SQL.
var (
	ReportCategories = []string{"sense", "bug", "ux", "content", "request", "noise"}
	ReportStatuses   = []string{"new", "issued", "dismissed"}
)

// A verdict is the thumb on a root's sense, sent as an improvement whose body
// is "sense good: <root>" or "sense bad: <root>" (app/lib/features/report).
// They arrive by the hundred and say one word each, so they are tallied by
// SenseVerdicts rather than listed, and a list can leave them out.
//
// A verdict is a body that is exactly that, for a root root_senses has — not
// one that merely starts like it. A reader who types "sense bad: the French
// for this is wrong" wrote a report, and a prefix match would hide it from the
// list and the export without the tally ever counting it. This one condition
// is what the list leaves out and what the tally counts, so nothing can fall
// between them. r is the reports row; s is root_senses.
const isVerdict = `r.kind = 'improvement'
   AND r.body IN ('sense good: ' || s.root_letters, 'sense bad: ' || s.root_letters)`

// ReportFilter narrows a list of reports by what the operator made of them —
// never by who sent them, which no column here could say.
type ReportFilter struct {
	Status          string // '' is every status
	ExcludeVerdicts bool
	Limit           int // 0 is ReportPage; capped at ReportExport
}

// Reports, newest first, and whether there were more than the limit. Reports
// are one-way: nothing the operator does here travels back to a device.
func (s *Store) Reports(ctx context.Context, f ReportFilter) ([]Report, bool, error) {
	limit := f.Limit
	if limit <= 0 {
		limit = ReportPage
	}
	limit = min(limit, ReportExport)
	// One past the limit, so a full page and a cut-short one can be told apart.
	rows, err := s.pool.Query(ctx, `
		SELECT id, kind, body, app_version, platform, screen, corpus_version, sense_version,
		       locale, sense_hash, coalesce(category, ''), status, coalesce(issue_url, ''), written_on
		  FROM reports r
		 WHERE ($1 = '' OR status = $1)
		   AND NOT ($2 AND EXISTS (SELECT 1 FROM root_senses s WHERE `+isVerdict+`))
		 ORDER BY written_on DESC, id LIMIT $3`, f.Status, f.ExcludeVerdicts, limit+1)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	out := []Report{}
	for rows.Next() {
		var r Report
		if err := rows.Scan(&r.ID, &r.Kind, &r.Body, &r.AppVersion, &r.Platform,
			&r.Screen, &r.CorpusVersion, &r.SenseVersion, &r.Locale, &r.SenseHash,
			&r.Category, &r.Status, &r.IssueURL, &r.WrittenOn); err != nil {
			return nil, false, err
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	if len(out) > limit {
		return out[:limit], true, nil
	}
	return out, false, nil
}

// ErrReportNotFound is a triage aimed at an id no report has.
var ErrReportNotFound = errors.New("report not found")

// TriageReport records what the operator made of one report. An empty
// category or issue URL clears it. The values are held to the column CHECKs,
// so a caller that skipped its own checks gets an error rather than a row.
//
// The retry is not a hedge. SweepReports takes every held row out and writes
// it back with the same id, in one statement, on its own clock. An UPDATE that
// queues behind it under READ COMMITTED waits for the old row, finds it gone
// when the sweep commits, and does not see the new one, which its snapshot
// predates — so it touches nothing and the operator's verdict is dropped
// without an error. A second statement takes a fresh snapshot and finds the
// row the sweep wrote. A second miss is an id that is really not there.
func (s *Store) TriageReport(ctx context.Context, id, category, status, issueURL string) error {
	for range 2 {
		tag, err := s.pool.Exec(ctx, `
			UPDATE reports SET category = nullif($2, ''), status = $3, issue_url = nullif($4, '')
			 WHERE id = $1`, id, category, status, issueURL)
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			return nil
		}
	}
	return ErrReportNotFound
}

// senseHashSQL is the sense_hash of a text, in SQL: the first twelve hex
// characters of the sha256 of its UTF-8 bytes. The app computes the same thing
// in Dart, and both sides are held to one shared vector, because a hash that
// differs by one byte of encoding makes every verdict read as cast against
// text since corrected.
func senseHashSQL(text string) string {
	return `left(encode(sha256(convert_to(` + text + `, 'UTF8')), 'hex'), 12)`
}

// senseVerdictsSQL tallies the thumbs per root and language. A verdict is
// matched by isVerdict, so the root that comes back is root_senses' own key
// rather than the body's text: a body is whatever a stranger typed, and a
// tally keyed on it would be a list of what strangers typed. The locale is the
// report's, which is a language and not a person, so the key is a sentence of
// ours in a language somebody reads it in.
//
// bad_on_current is the bad verdicts cast against the text served today: the
// report's sense_hash matches the hash of the sentence the app showed in that
// locale. Anything French gets sense_fr, everything else sense_en, which is
// the app's own rule (app/lib/data/root_repo.dart). A bad verdict on a
// sentence since corrected drops out of it, so a root at the top of this list
// is one whose current text is judged wrong.
var senseVerdictsSQL = `
SELECT s.root_letters, r.locale,
       count(*) FILTER (WHERE r.body = 'sense good: ' || s.root_letters) AS good,
       count(*) FILTER (WHERE r.body = 'sense bad: ' || s.root_letters) AS bad,
       count(*) FILTER (WHERE r.body = 'sense bad: ' || s.root_letters AND r.sense_hash = ` +
	senseHashSQL(`CASE WHEN r.locale = 'fr' THEN s.sense_fr ELSE s.sense_en END`) + `) AS bad_on_current
  FROM reports r
  JOIN root_senses s ON ` + isVerdict + `
 GROUP BY s.root_letters, r.locale
 ORDER BY bad_on_current DESC, bad DESC, s.root_letters, r.locale`

// A SenseVerdict is the thumbs on one root's sense in one language.
type SenseVerdict struct {
	Root         string `json:"root"`
	Locale       string `json:"locale"`
	Good         int64  `json:"good"`
	Bad          int64  `json:"bad"`
	BadOnCurrent int64  `json:"bad_on_current"`
}

// SenseVerdicts, worst first: the roots whose text as served today is most
// often judged wrong.
func (s *Store) SenseVerdicts(ctx context.Context) ([]SenseVerdict, error) {
	rows, err := s.pool.Query(ctx, senseVerdictsSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []SenseVerdict{}
	for rows.Next() {
		var v SenseVerdict
		if err := rows.Scan(&v.Root, &v.Locale, &v.Good, &v.Bad, &v.BadOnCurrent); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
