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
