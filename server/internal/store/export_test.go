package store

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// ApplyInTx lets a test land an op without committing it, so two writes can
// be held in flight at once and the order they commit in can be chosen.
func (s *Store) ApplyInTx(ctx context.Context, tx pgx.Tx, userID string, op Op) OpResult {
	return applyInTx(ctx, tx, userID, op)
}

// AdminAggregates is every statement the dashboard can cause to run, so a test
// can hold them to the rule that none of them may be about one reader.
var AdminAggregates = adminAggregates

// SenseVerdictsSQL is the one aggregate keyed on something other than a
// number, so the test that holds the rest to numbers can name its exception.
var SenseVerdictsSQL = senseVerdictsSQL

// SweepReportsSQL lets a test hold a sweep open while something else runs.
var SweepReportsSQL = sweepReportsSQL

// SenseHashSQL is the sense_hash expression, so a test can hold it to the
// vector the app is held to.
var SenseHashSQL = senseHashSQL
