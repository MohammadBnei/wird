package store_test

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// The failure: a reader marks an aya understood on a plane on Monday, the
// phone finds a signal on Friday, and the tablet — which synced on
// Wednesday — is never told. The write is on the server and invisible
// forever, because the instant it carries is one the tablet's cursor has
// already walked past.
func TestAnAyaUnderstoodOfflineReachesATabletThatAlreadySyncedPastThatInstant(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-flight")

	land(t, db, user, understood(opID(1), 2255, time.Now().Add(-time.Hour)))
	wednesday := pull(t, db, user, "")
	if len(wednesday.Changes) != 1 {
		t.Fatalf("the tablet's first sync carried %d rows, expected the one aya", len(wednesday.Changes))
	}

	land(t, db, user, understood(opID(2), 96001, time.Now().Add(-4*24*time.Hour)))

	friday := pull(t, db, user, wednesday.Cursor)
	if !carries(t, friday, 96001) {
		t.Fatalf("the aya understood offline never reached the other device: %+v", friday.Changes)
	}
}

// The failure: two writes land at once, the one that took the lower place in
// the change order commits second, and a tablet that synced in between has a
// cursor past it. Same loss as the one above, one layer down — a sequence
// number is handed out when the INSERT runs, not when it commits.
func TestAWriteStillInFlightWhenTheTabletSyncsIsNotSkippedOnceItCommits(t *testing.T) {
	db, pool := testenv.Postgres(t)
	ctx := t.Context()
	user := reader(t, db, "sub-race")

	slow, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin the slow write: %v", err)
	}
	defer func() { _ = slow.Rollback(ctx) }()
	if r := db.ApplyInTx(ctx, slow, user, understood(opID(1), 96001, time.Now())); r.Status != store.OpApplied {
		t.Fatalf("the slow write did not land: %+v", r)
	}

	// A second write, made while the first is still in flight. Left to
	// itself it takes the later place in the order and commits first.
	quick := make(chan store.OpResult, 1)
	go func() {
		results, err := db.Apply(ctx, user, []store.Op{understood(opID(2), 96002, time.Now())})
		if err != nil || len(results) != 1 {
			quick <- store.OpResult{Status: "no answer", Reason: fmt.Sprint(err)}
			return
		}
		quick <- results[0]
	}()
	var second store.OpResult
	settled := false
	select {
	case second = <-quick:
		settled = true
	case <-time.After(750 * time.Millisecond):
	}

	middle := pull(t, db, user, "")

	if err := slow.Commit(ctx); err != nil {
		t.Fatalf("commit the slow write: %v", err)
	}
	if !settled {
		select {
		case second = <-quick:
		case <-time.After(30 * time.Second):
			t.Fatal("the second write never finished")
		}
	}
	if second.Status != store.OpApplied {
		t.Fatalf("the second write did not land: %+v", second)
	}

	after := pull(t, db, user, middle.Cursor)
	if !carries(t, middle, 96001) && !carries(t, after, 96001) {
		t.Fatalf("the write that was in flight during the sync was never handed over: middle %+v, then %+v",
			middle.Changes, after.Changes)
	}
	if !carries(t, middle, 96002) && !carries(t, after, 96002) {
		t.Fatalf("the write made during the sync was never handed over: middle %+v, then %+v",
			middle.Changes, after.Changes)
	}
}

// The failure: a reader syncs over and over, and the cursor either hands the
// same row back every time — re-applying the whole history on every
// reconnect — or steps over one and loses it.
func TestNoWriteIsHandedOverTwiceOrMissedAcrossManySyncs(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-many")

	const writes = 40
	seen := map[int]int{}
	cursor := ""
	for i := 1; i <= writes; i++ {
		// The instants walk backwards: a phone that has been offline for
		// weeks flushes its oldest write last.
		land(t, db, user, understood(opID(i), 2000+i, time.Now().Add(-time.Duration(i)*24*time.Hour)))
		page := pull(t, db, user, cursor)
		cursor = page.Cursor
		for _, c := range page.Changes {
			seen[ayahOf(t, c)]++
		}
	}
	if last := pull(t, db, user, cursor); len(last.Changes) != 0 {
		t.Fatalf("a pull past the end handed %d rows back again", len(last.Changes))
	}
	for i := 1; i <= writes; i++ {
		switch n := seen[2000+i]; n {
		case 1:
		case 0:
			t.Errorf("aya %d was marked understood and never handed over", 2000+i)
		default:
			t.Errorf("aya %d was handed over %d times", 2000+i, n)
		}
	}
}

func understood(id string, ayah int, at time.Time) store.Op {
	body, err := json.Marshal(map[string]any{"ayah_ids": []int{ayah}, "understood_at": at})
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: "ayah_understood", Body: body}
}

func opID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012d", n) }

func land(t *testing.T, db *store.Store, user string, op store.Op) {
	t.Helper()
	results, err := db.Apply(t.Context(), user, []store.Op{op})
	if err != nil {
		t.Fatalf("flush %s: %v", op.ClientOpID, err)
	}
	if results[0].Status != store.OpApplied {
		t.Fatalf("flush %s: %s %s", op.ClientOpID, results[0].Status, results[0].Reason)
	}
}

func pull(t *testing.T, db *store.Store, user, cursor string) store.Changes {
	t.Helper()
	page, err := db.Changes(t.Context(), user, cursor)
	if err != nil {
		t.Fatalf("pull from %q: %v", cursor, err)
	}
	return page
}

func carries(t *testing.T, page store.Changes, ayah int) bool {
	t.Helper()
	for _, c := range page.Changes {
		if ayahOf(t, c) == ayah {
			return true
		}
	}
	return false
}

func ayahOf(t *testing.T, c store.Change) int {
	t.Helper()
	var row struct {
		AyahID int `json:"ayah_id"`
	}
	if err := json.Unmarshal(c.Row, &row); err != nil {
		t.Fatalf("unreadable %s row: %v", c.Kind, err)
	}
	return row.AyahID
}
