package store_test

import (
	"sync"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// The hazard the sequence introduces: a number is handed out when the INSERT
// runs, not when it commits. Writers racing means a lower number can become
// visible after a higher one, and a reader whose cursor walked past it never
// hears about that row again.
//
// This is the undirected version: many writers at once, a reader pulling
// through the whole time, and the question is only whether every write the
// server accepted is handed over exactly once.
func TestNothingIsSkippedWhileManyWritesLandAtOnce(t *testing.T) {
	db, _ := testenv.Postgres(t)
	ctx := t.Context()
	user := reader(t, db, "sub-hammer")

	const writers, each = 8, 12
	done := make(chan struct{})
	var wg sync.WaitGroup
	for w := range writers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range each {
				ayah := 1000*(w+1) + i + 1
				op := understood(opID(w*1000+i+1), ayah, time.Now())
				results, err := db.Apply(ctx, user, []store.Op{op})
				if err != nil {
					t.Errorf("flush %d: %v", ayah, err)
					return
				}
				if results[0].Status != store.OpApplied {
					t.Errorf("flush %d: %s %s", ayah, results[0].Status, results[0].Reason)
					return
				}
			}
		}()
	}

	// The reader, syncing the whole time the writes are landing.
	seen := map[int]int{}
	var readerWG sync.WaitGroup
	readerWG.Add(1)
	go func() {
		defer readerWG.Done()
		cursor := ""
		for {
			page := pull(t, db, user, cursor)
			cursor = page.Cursor
			for _, c := range page.Changes {
				seen[ayahOf(t, c)]++
			}
			select {
			case <-done:
				// One last sweep after the writers are finished.
				for {
					page := pull(t, db, user, cursor)
					if len(page.Changes) == 0 {
						return
					}
					cursor = page.Cursor
					for _, c := range page.Changes {
						seen[ayahOf(t, c)]++
					}
				}
			default:
			}
		}
	}()

	wg.Wait()
	close(done)
	readerWG.Wait()

	for w := range writers {
		for i := range each {
			ayah := 1000*(w+1) + i + 1
			switch n := seen[ayah]; n {
			case 1:
			case 0:
				t.Errorf("aya %d landed on the server and was never handed over", ayah)
			default:
				t.Errorf("aya %d was handed over %d times", ayah, n)
			}
		}
	}
}

// The page boundary. A reader restoring years of progress crosses it many
// times, and a cursor that is off by one at the seam loses a row per page or
// hands one back forever.
func TestEveryRowCrossesThePageBoundaryExactlyOnce(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-pages")

	const writes = store.ChangePage*2 + 7
	for i := range writes {
		land(t, db, user, understood(opID(i+1), 1000*((i/200)+1)+(i%200)+1, time.Now()))
	}

	seen := map[int]int{}
	cursor := ""
	pages := 0
	for {
		page := pull(t, db, user, cursor)
		if len(page.Changes) == 0 {
			break
		}
		pages++
		if pages > 10 {
			t.Fatal("the cursor is not advancing: the same page keeps coming back")
		}
		cursor = page.Cursor
		for _, c := range page.Changes {
			seen[ayahOf(t, c)]++
		}
		if !page.More {
			break
		}
	}
	if len(seen) != writes {
		t.Errorf("%d ayas were written and %d distinct ones were handed over", writes, len(seen))
	}
	for ayah, n := range seen {
		if n != 1 {
			t.Errorf("aya %d was handed over %d times", ayah, n)
		}
	}
	if last := pull(t, db, user, cursor); len(last.Changes) != 0 {
		t.Errorf("a pull past the end handed %d rows back again", len(last.Changes))
	}
}
