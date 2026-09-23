package api_test

import (
	"net/http"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
)

// prayed is the one op a current device sends when a prayer ends: the range
// it was prayed on, the order it was read in, and the id those two derive.
func prayed(clientOpID, readingOrder string, start, end int, at time.Time) store.Op {
	return op(clientOpID, "set_prayed", map[string]any{
		"set_id":        store.SetID(readingOrder, start, end),
		"start_ayah_id": start,
		"end_ayah_id":   end,
		"reading_order": readingOrder,
		"prayed_at":     at,
	})
}

func (h *harness) progress(t *testing.T, token string) store.Progress {
	t.Helper()
	var p store.Progress
	decode(t, h.get(t, "/v1/progress", token), http.StatusOK, &p)
	return p
}

func applied(t *testing.T, results map[string]store.OpResult, ops ...store.Op) {
	t.Helper()
	for _, o := range ops {
		if got := results[o.ClientOpID]; got.Status != store.OpApplied {
			t.Fatalf("%s came back %+v, so the reader's prayer is not counted", o.Kind, got)
		}
	}
}

// The failure: the reader prays the same five ayas on Monday and on Tuesday,
// and their list shows two sets of the same range. A set is a range, not an
// event, so the second prayer belongs to the first set.
func TestTheSameRangePrayedTwiceIsOneSetAndTwoPrayers(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-twice")

	monday := prayed(opID(1), "nuzul", 96001, 96005, noon)
	tuesday := prayed(opID(2), "nuzul", 96001, 96005, noon.Add(24*time.Hour))
	applied(t, h.flush(t, token, monday), monday)
	applied(t, h.flush(t, token, tuesday), tuesday)

	p := h.progress(t, token)
	if p.Sets != 1 {
		t.Fatalf("one range prayed twice made %d sets", p.Sets)
	}
	if p.Prayers != 2 {
		t.Fatalf("two prayers prayed, %d counted", p.Prayers)
	}

	// The tablet hears about both halves of that one op, and about the set
	// before the prayers that name it.
	page := h.pull(t, token, "")
	var sets, prayers int
	for _, c := range page.Changes {
		switch c.Kind {
		case "sets":
			sets++
			if prayers > 0 {
				t.Fatal("a prayer reached the second device before the set it belongs to")
			}
		case "set_prayers":
			prayers++
		}
	}
	if sets != 1 || prayers != 2 {
		t.Fatalf("the change stream carried %d sets and %d prayers: %+v", sets, prayers, page.Changes)
	}
}

// The failure: the phone and the tablet both pray the same range while
// offline, and the second one to reach the server is refused for colliding
// with the first — which dead-letters that prayer permanently.
func TestTheSameRangePrayedFromTwoDevicesIsOneSetTwoPrayersAndNothingIsRefused(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-two-devices-one-set")

	phone := prayed(opID(1), "nuzul", 2255, 2255, noon)
	tablet := prayed(opID(2), "nuzul", 2255, 2255, noon.Add(time.Hour))

	// Two reconnects, in whichever order the network allowed.
	applied(t, h.flush(t, token, phone), phone)
	applied(t, h.flush(t, token, tablet), tablet)

	p := h.progress(t, token)
	if p.Sets != 1 || p.Prayers != 2 {
		t.Fatalf("two devices on one range made %d sets and %d prayers", p.Sets, p.Prayers)
	}
}

// The failure: the reader reinstalls, prays the range they were working on,
// and the server records a second set for it — so "the fourth prayer on this
// set" restarts at one and the ratio on screen 1d halves.
func TestAReinstallPrayingTheSameRangeDoesNotCreateASecondSet(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-reinstall")

	before := prayed(opID(1), "nuzul", 112001, 112004, noon)
	applied(t, h.flush(t, token, before), before)

	// A fresh install: no outbox, no local ids, nothing but the range and the
	// order, from which the same set id falls out.
	after := prayed(opID(2), "nuzul", 112001, 112004, noon.Add(72*time.Hour))
	applied(t, h.flush(t, token, after), after)

	p := h.progress(t, token)
	if p.Sets != 1 {
		t.Fatalf("a reinstall made %d sets out of one range", p.Sets)
	}
	if p.Prayers != 2 {
		t.Fatalf("two prayers prayed across a reinstall, %d counted", p.Prayers)
	}
}

// The failure: a device derives set ids differently from this server and the
// mismatch is stored, so months later the same range is two sets and neither
// count is right. A wrong id is refused at the door instead.
func TestASetIdThatDoesNotMatchItsOwnRangeIsRefusedRatherThanStored(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-wrong-id")

	wrong := []store.Op{
		// The id of a different range.
		op(opID(1), "set_prayed", map[string]any{
			"set_id":        store.SetID("nuzul", 96001, 96005),
			"start_ayah_id": 96001, "end_ayah_id": 96003,
			"reading_order": "nuzul", "prayed_at": noon,
		}),
		// The id of the same range in the other reading order.
		op(opID(2), "set_prayed", map[string]any{
			"set_id":        store.SetID("mushaf", 96001, 96005),
			"start_ayah_id": 96001, "end_ayah_id": 96005,
			"reading_order": "nuzul", "prayed_at": noon,
		}),
		// A freshly minted uuid, which is what the old device did.
		op(opID(3), "set_prayed", map[string]any{
			"set_id":        "88888888-8888-4888-8888-888888888888",
			"start_ayah_id": 96001, "end_ayah_id": 96005,
			"reading_order": "nuzul", "prayed_at": noon,
		}),
		// A range that is not a range of ayas at all.
		op(opID(4), "set_prayed", map[string]any{
			"set_id":        store.SetID("nuzul", 115001, 115005),
			"start_ayah_id": 115001, "end_ayah_id": 115005,
			"reading_order": "nuzul", "prayed_at": noon,
		}),
	}

	results := h.flush(t, token, wrong...)
	for _, o := range wrong {
		got := results[o.ClientOpID]
		if got.Status != store.OpRefused {
			t.Fatalf("a set id that does not match its range came back %+v", got)
		}
		if got.Reason == "" {
			t.Fatal("the refusal carries no reason, so settings has nothing to show the reader")
		}
	}

	if p := h.progress(t, token); p.Sets != 0 || p.Prayers != 0 {
		t.Fatalf("refused ops still stored %d sets and %d prayers", p.Sets, p.Prayers)
	}
}

// The failure: the flush timed out after the server applied it, the phone
// sends the same op again, and the reader's prayer count goes up twice for
// one prayer.
func TestReplayingOnePrayerOpCountsOnePrayerAndOneSet(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-replay-one-op")

	once := prayed(opID(1), "mushaf", 1001, 1007, noon)
	applied(t, h.flush(t, token, once), once)

	for attempt := 2; attempt <= 4; attempt++ {
		if got := h.flush(t, token, once)[once.ClientOpID]; got.Status != store.OpDuplicate {
			t.Fatalf("reconnect %d came back %+v, which is a prayer counted twice", attempt, got)
		}
	}

	if p := h.progress(t, token); p.Prayers != 1 || p.Sets != 1 {
		t.Fatalf("one op sent four times counted %d prayers on %d sets", p.Prayers, p.Sets)
	}
}

// The failure: set ids are derived, so every reader who prays al-Fātiḥa
// derives the same uuid. If that id were the reader's own, the second reader
// to pray it would be refused for life.
func TestTwoReadersPrayingTheSameRangeEachGetTheirOwnSet(t *testing.T) {
	h := newHarness(t)
	first := h.tokenFor(t, "sub-first-reader")
	second := h.tokenFor(t, "sub-second-reader")

	hers := prayed(opID(1), "mushaf", 1001, 1007, noon)
	his := prayed(opID(2), "mushaf", 1001, 1007, noon.Add(time.Hour))
	applied(t, h.flush(t, first, hers), hers)
	applied(t, h.flush(t, second, his), his)

	for _, token := range []string{first, second} {
		if p := h.progress(t, token); p.Sets != 1 || p.Prayers != 1 {
			t.Fatalf("a reader sees %d sets and %d prayers of their own", p.Sets, p.Prayers)
		}
	}
}

// The failure: a phone that has not updated still numbers its own sets, and
// its second set claims a number the first already has. That collision is
// refused forever, and the prayer on the refused set dies with it.
func TestAPhoneThatStillSendsItsOwnOrdinalDoesNotCollideOnItsSecondSet(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-old-phone")

	// Both sets say they are the first, which is what a reinstall sends.
	old := []store.Op{aSet("33333333-3333-4333-8333-333333333333", 1),
		aSet("44444444-4444-4444-8444-444444444444", 1)}
	results := h.flush(t, token, old...)
	applied(t, results, old...)

	// And a current device on the same account, whose set is numbered after them.
	current := prayed(opID(9), "nuzul", 2255, 2255, noon)
	applied(t, h.flush(t, token, current), current)

	if p := h.progress(t, token); p.Sets != 3 {
		t.Fatalf("three sets were recorded and %d survived", p.Sets)
	}
	var ordinals []int
	rows, err := h.pool.Query(t.Context(),
		`SELECT ordinal FROM sets WHERE user_id = (SELECT id FROM users LIMIT 1) ORDER BY ordinal`)
	if err != nil {
		t.Fatalf("read ordinals: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var n int
		if err := rows.Scan(&n); err != nil {
			t.Fatalf("scan ordinal: %v", err)
		}
		ordinals = append(ordinals, n)
	}
	if len(ordinals) != 3 || ordinals[0] != 1 || ordinals[1] != 2 || ordinals[2] != 3 {
		t.Fatalf("the server numbered the reader's sets %v", ordinals)
	}
}
