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
