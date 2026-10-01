package store_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

func moved(id string, surah int, word int64, at time.Time) store.Op {
	body, err := json.Marshal(map[string]any{"surah_id": surah, "word_id": word, "updated_at": at})
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: "position_moved", Body: body}
}

// positionIn is the word the stream says the reader stands on in a sūra, and
// 0 when it carries no position there.
func positionIn(t *testing.T, page store.Changes, surah int) int64 {
	t.Helper()
	for _, c := range page.Changes {
		if c.Kind != "reading_positions" {
			continue
		}
		var row struct {
			SurahID int   `json:"surah_id"`
			WordID  int64 `json:"word_id"`
		}
		if err := json.Unmarshal(c.Row, &row); err != nil {
			t.Fatal(err)
		}
		if row.SurahID == surah {
			return row.WordID
		}
	}
	return 0
}

// The failure: the phone reads on to 2:260 offline, the tablet is opened at
// 2:255 later in the day but its move was made earlier, and the phone's flush
// lands last. Whichever lands last wins, and the reader is sent back.
func TestAnOlderPositionThatLandsLastSendsTheReaderBack(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-positions")
	now := time.Now()

	land(t, db, user, moved(opID(1), 2, 2260001, now.Add(-time.Minute)))
	land(t, db, user, moved(opID(2), 2, 2255003, now.Add(-time.Hour)))

	if got := positionIn(t, pull(t, db, user, ""), 2); got != 2260001 {
		t.Fatalf("the reader stands on %d after an older move landed, want 2260001", got)
	}
}

// The failure: a move updates the row in place and keeps its old seq, so a
// device that already pulled past it is never told the reader moved on.
func TestAPositionMovedAfterAPullNeverReachesTheDeviceThatPulled(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-positions-seq")
	now := time.Now()

	land(t, db, user, moved(opID(1), 1, 1001001, now.Add(-time.Hour)))
	first := pull(t, db, user, "")
	land(t, db, user, moved(opID(2), 1, 1004002, now))

	if got := positionIn(t, pull(t, db, user, first.Cursor), 1); got != 1004002 {
		t.Fatalf("a pull after the move carried %d, want the new position 1004002", got)
	}
}

// The failure: a phone whose clock runs days ahead writes once, and every
// later move from a correctly set device loses to it until that day comes.
func TestAPhoneWithItsClockAheadPinsThePositionForDays(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-positions-clock")

	if got := status(t, db, user, moved(opID(1), 2, 2255003, time.Now().Add(72*time.Hour))); got != store.OpRefused {
		t.Fatalf("a position dated three days ahead came back %q, want refused", got)
	}
}

// The failure: a position names a word outside its sūra, or one that is not
// a word at all, and another device opens a reading screen on nothing.
func TestAPositionNamingAWordOutsideItsSuraIsStored(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-positions-bad")
	now := time.Now()

	for i, op := range []store.Op{
		moved(opID(1), 2, 1001001, now),     // a word of 1, filed under 2
		moved(opID(2), 115, 115001001, now), // no sūra 115
		moved(opID(3), 2, 2255000, now),     // position 0
		moved(opID(4), 2, 2000001, now),     // aya 0
		moved(opID(5), 2, 2255003, time.Time{}),
	} {
		if got := status(t, db, user, op); got != store.OpRefused {
			t.Errorf("bad position %d came back %q, want refused", i+1, got)
		}
	}
}
