package store_test

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// A background flush that passed the deletion check a moment before the
// delete committed would mint the reader back under a new id, and its outbox
// would refill the account the reader just deleted. Raced many times, because
// the window is a few statements wide.
func TestARequestInFlightDuringTheDeletionBringsTheAccountBack(t *testing.T) {
	db, pool := testenv.Postgres(t)
	signedIn := time.Now().Add(-time.Hour)

	for i := range 50 {
		subject := "sub-racing-" + string(rune('a'+i%26)) + string(rune('a'+i/26))
		if _, err := db.ReaderFor(t.Context(), subject, signedIn); err != nil {
			t.Fatalf("first sign-in: %v", err)
		}
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			_, err := db.ReaderFor(t.Context(), subject, signedIn)
			if err != nil && !errors.Is(err, store.ErrDeleted) {
				t.Errorf("flush: %v", err)
			}
		}()
		go func() {
			defer wg.Done()
			if err := db.DeleteReader(t.Context(), subject); err != nil {
				t.Errorf("delete: %v", err)
			}
		}()
		wg.Wait()

		var n int
		if err := pool.QueryRow(t.Context(), `SELECT count(*) FROM users WHERE oidc_subject = $1`, subject).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("round %d: the deleted reader exists again", i)
		}
	}
}
