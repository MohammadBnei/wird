package api_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
)

// post sends a batch the way a device does: one token, one body, the answer
// read back per op.
func (h *harness) post(t *testing.T, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("encode request: %v", err)
	}
	r := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(encoded))
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.routes.ServeHTTP(w, r)
	return w
}

// flush is one reconnect: the device hands over its queue and reads the
// verdict on each op separately.
func (h *harness) flush(t *testing.T, token string, ops ...store.Op) map[string]store.OpResult {
	t.Helper()
	w := h.post(t, "/v1/sync", token, map[string]any{"ops": ops})
	var answer struct {
		Results []store.OpResult `json:"results"`
	}
	decode(t, w, http.StatusOK, &answer)
	if len(answer.Results) != len(ops) {
		t.Fatalf("sent %d ops and got %d verdicts: a device cannot tell which of its writes landed",
			len(ops), len(answer.Results))
	}
	byID := map[string]store.OpResult{}
	for _, r := range answer.Results {
		byID[r.ClientOpID] = r
	}
	return byID
}

func (h *harness) keptList(t *testing.T, token string) []store.KeptItem {
	t.Helper()
	var answer struct {
		Items []store.KeptItem `json:"items"`
	}
	decode(t, h.get(t, "/v1/kept", token), http.StatusOK, &answer)
	return answer.Items
}

func (h *harness) pull(t *testing.T, token, cursor string) store.Changes {
	t.Helper()
	var page store.Changes
	decode(t, h.get(t, "/v1/changes?since="+cursor, token), http.StatusOK, &page)
	return page
}

func op(id, kind string, body any) store.Op {
	encoded, err := json.Marshal(body)
	if err != nil {
		panic(err)
	}
	return store.Op{ClientOpID: id, Kind: kind, Body: encoded}
}

// opID makes a uuid out of a number so a test can read which op is which.
func opID(n int) string {
	return fmt.Sprintf("00000000-0000-4000-8000-%012d", n)
}

var noon = time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

func aSet(id string, ordinal int) store.Op {
	return op(id, "set_recorded", map[string]any{
		"id": id, "ordinal": ordinal, "start_ayah_id": 96001, "end_ayah_id": 96005,
		"reading_order": "nuzul", "created_at": noon,
	})
}

// The failure: a flush that timed out after the server had already applied it
// is sent again on the next reconnect, and the reader's prayer count goes up
// twice for one prayer. That number is the one the app exists to show, and it
// is never corrected.
func TestAReplayedFlushCountsOnePrayerNotTwo(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-replay")

	setID := "11111111-1111-4111-8111-111111111111"
	prayer := op(opID(2), "set_prayed", map[string]any{
		"id": "22222222-2222-4222-8222-222222222222", "set_id": setID,
		"prayer_name": "fajr", "prayed_at": noon,
	})
	understood := op(opID(3), "ayah_understood", map[string]any{
		"ayah_ids": []int{96001, 96002, 96003}, "understood_at": noon,
	})
	batch := []store.Op{aSet(setID, 1), prayer, understood}

	first := h.flush(t, token, batch...)
	for _, o := range batch {
		if first[o.ClientOpID].Status != store.OpApplied {
			t.Fatalf("first flush of %s: %+v", o.Kind, first[o.ClientOpID])
		}
	}

	// The same queue, twice more: the phone reconnected, lost the answer, and
	// tried again.
	for attempt := 2; attempt <= 3; attempt++ {
		again := h.flush(t, token, batch...)
		for _, o := range batch {
			if again[o.ClientOpID].Status != store.OpDuplicate {
				t.Fatalf("reconnect %d applied %s a second time: %+v", attempt, o.Kind, again[o.ClientOpID])
			}
		}
	}

	var p store.Progress
	decode(t, h.get(t, "/v1/progress", token), http.StatusOK, &p)
	if p.Prayers != 1 {
		t.Fatalf("one prayer prayed, %d counted", p.Prayers)
	}
	if p.Sets != 1 {
		t.Fatalf("one set read, %d counted", p.Sets)
	}
	if p.Understood != 3 {
		t.Fatalf("three ayas understood, %d counted", p.Understood)
	}
}

// The failure: a flush is cut off halfway — the socket dies, the server
// answers 500 after ten of twenty ops. The device resends the whole queue.
// The ten that landed must not land again, and the ten that did not must land.
func TestAFlushCutOffHalfwayFinishesOnTheRetryWithoutDoublingWhatLanded(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-halfway")

	setID := "33333333-3333-4333-8333-333333333333"
	h.flush(t, token, aSet(setID, 1))

	prayers := make([]store.Op, 20)
	for i := range prayers {
		prayers[i] = op(opID(100+i), "set_prayed", map[string]any{
			"id":          fmt.Sprintf("44444444-4444-4444-8444-%012d", i),
			"set_id":      setID,
			"prayer_name": "isha",
			"prayed_at":   noon.Add(time.Duration(i) * time.Minute),
		})
	}

	// The half the server got to before the connection died.
	h.flush(t, token, prayers[:10]...)
	// The device kept all twenty, because it never read an answer.
	retry := h.flush(t, token, prayers...)

	for i, o := range prayers {
		want := store.OpApplied
		if i < 10 {
			want = store.OpDuplicate
		}
		if retry[o.ClientOpID].Status != want {
			t.Fatalf("prayer %d came back %+v, wanted %s", i, retry[o.ClientOpID], want)
		}
	}

	var p store.Progress
	decode(t, h.get(t, "/v1/progress", token), http.StatusOK, &p)
	if p.Prayers != 20 {
		t.Fatalf("twenty prayers prayed, %d counted", p.Prayers)
	}
}

// The failure the plan names: one op the server will never accept sits at the
// head of the queue and holds the other nineteen behind it on every reconnect,
// so the reader silently loses everything they did.
func TestAPoisonOpDoesNotBlockTheNineteenWritesBehindIt(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-poison")

	// A prayer against a set this account does not have — the plan's own
	// example of a poison op.
	poison := op(opID(1), "set_prayed", map[string]any{
		"id":          "55555555-5555-4555-8555-555555555555",
		"set_id":      "99999999-9999-4999-8999-999999999999",
		"prayer_name": "maghrib",
		"prayed_at":   noon,
	})

	ops := []store.Op{poison}
	for i := range 19 {
		ops = append(ops, op(opID(200+i), "ayah_understood", map[string]any{
			"ayah_ids": []int{96001 + i}, "understood_at": noon,
		}))
	}

	results := h.flush(t, token, ops...)
	if got := results[poison.ClientOpID]; got.Status != store.OpRefused {
		t.Fatalf("the poison op came back %+v; a device cannot tell it to stop resending", got)
	}
	if results[poison.ClientOpID].Reason == "" {
		t.Fatal("the refusal carries no reason, so settings has nothing to show the reader")
	}
	for _, o := range ops[1:] {
		if results[o.ClientOpID].Status != store.OpApplied {
			t.Fatalf("a good write behind the poison op came back %+v", results[o.ClientOpID])
		}
	}

	var p store.Progress
	decode(t, h.get(t, "/v1/progress", token), http.StatusOK, &p)
	if p.Understood != 19 {
		t.Fatalf("nineteen writes were queued behind one bad one and %d landed", p.Understood)
	}

	// And it stays refused however often the device tries, which is what makes
	// the client's five attempts terminate instead of looping forever.
	for attempt := 2; attempt <= 5; attempt++ {
		if got := h.flush(t, token, poison)[poison.ClientOpID]; got.Status != store.OpRefused {
			t.Fatalf("attempt %d of the poison op came back %+v", attempt, got)
		}
	}
}

// The failure: the reader deletes a note on the phone and the tablet hands it
// straight back on the next pull, forever. A delete has to travel as a row,
// not as an absence.
func TestAKeptItemDeletedOnThePhoneStaysDeletedOnTheTablet(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-two-devices")
	const note = "66666666-6666-4666-8666-666666666666"

	// The phone keeps a note and flushes.
	h.flush(t, token, op(opID(1), "kept_upsert", map[string]any{
		"id": note, "kind": "note", "ayah_id": 96001, "root_letters": nil,
		"body": "the first word revealed", "tags": []string{"revisit"},
		"created_at": noon, "updated_at": noon,
	}))

	// The tablet pulls and holds it.
	tablet := h.pull(t, token, "")
	if !holds(tablet, note) {
		t.Fatalf("the tablet never received the note: %+v", tablet.Changes)
	}

	// The phone deletes it and flushes.
	h.flush(t, token, op(opID(2), "kept_delete", map[string]any{
		"id": note, "deleted_at": noon.Add(time.Hour),
	}))

	// The tablet pulls again from where it left off.
	after := h.pull(t, token, tablet.Cursor)
	tombstone, found := change(after, note)
	if !found {
		t.Fatal("the delete never reached the tablet, so the note is still on its list")
	}
	var row struct {
		DeletedAt *time.Time `json:"deleted_at"`
	}
	if err := json.Unmarshal(tombstone.Row, &row); err != nil {
		t.Fatalf("tombstone row: %v", err)
	}
	if row.DeletedAt == nil {
		t.Fatalf("the row came back alive: %s", tombstone.Row)
	}

	// And the server's own read model agrees, so a third device that syncs
	// from scratch does not resurrect it either.
	kept := h.keptList(t, token)
	if len(kept) != 0 {
		t.Fatalf("a deleted note is still on the kept list: %+v", kept)
	}
}

// The failure: the tablet asks for what changed and is handed the reader's
// whole history again, every time, because the cursor it was given does not
// move.
func TestASecondPullDoesNotHandBackWhatTheDeviceAlreadyHas(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-cursor")

	h.flush(t, token, op(opID(1), "ayah_understood", map[string]any{
		"ayah_ids": []int{96001, 96002}, "understood_at": noon,
	}))

	first := h.pull(t, token, "")
	if len(first.Changes) != 2 {
		t.Fatalf("first pull carried %d rows, expected the two ayas", len(first.Changes))
	}
	if first.Cursor == "" {
		t.Fatal("no cursor came back, so the next pull must start from the beginning")
	}

	if again := h.pull(t, token, first.Cursor); len(again.Changes) != 0 {
		t.Fatalf("the same rows came back a second time: %+v", again.Changes)
	}

	// One new write, and only that one arrives.
	h.flush(t, token, op(opID(2), "ayah_understood", map[string]any{
		"ayah_ids": []int{96003}, "understood_at": noon.Add(time.Hour),
	}))
	third := h.pull(t, token, first.Cursor)
	if len(third.Changes) != 1 {
		t.Fatalf("the incremental pull carried %d rows, expected one: %+v", len(third.Changes), third.Changes)
	}
}

// The failure: one reader's device sends an op naming another reader's kept
// item and edits or deletes it. Ids are minted on devices, so a guessed id
// must not be authority over somebody else's note.
func TestOneReadersOpCannotTouchAnotherReadersNote(t *testing.T) {
	h := newHarness(t)
	owner := h.tokenFor(t, "sub-owner")
	stranger := h.tokenFor(t, "sub-stranger")
	const note = "77777777-7777-4777-8777-777777777777"

	h.flush(t, owner, op(opID(1), "kept_upsert", map[string]any{
		"id": note, "kind": "note", "ayah_id": nil, "root_letters": nil,
		"body": "mine", "tags": []string{}, "created_at": noon, "updated_at": noon,
	}))

	// The stranger tries to overwrite it, then to delete it.
	h.flush(t, stranger, op(opID(2), "kept_upsert", map[string]any{
		"id": note, "kind": "note", "ayah_id": nil, "root_letters": nil,
		"body": "theirs", "tags": []string{}, "created_at": noon,
		"updated_at": noon.Add(time.Hour),
	}))
	h.flush(t, stranger, op(opID(3), "kept_delete", map[string]any{
		"id": note, "deleted_at": noon.Add(2 * time.Hour),
	}))

	kept := h.keptList(t, owner)
	if len(kept) != 1 || kept[0].Body != "mine" {
		t.Fatalf("a stranger reached the owner's note: %+v", kept)
	}

	theirs := h.keptList(t, stranger)
	if len(theirs) != 0 {
		t.Fatalf("the stranger's write landed on their own account instead of being refused: %+v", theirs)
	}
}

// The failure: an older phone sends a body the server cannot read and the
// server takes the whole batch down with a 500, so the device retries the same
// unreadable queue on every reconnect.
func TestAnOpTheServerCannotReadIsRefusedAloneAndNotAsA500(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-garbage")

	results := h.flush(t, token,
		store.Op{ClientOpID: opID(1), Kind: "ayah_understood", Body: json.RawMessage(`{"ayah_ids":"all of them"}`)},
		store.Op{ClientOpID: opID(2), Kind: "a kind this server has never heard of", Body: json.RawMessage(`{}`)},
		store.Op{ClientOpID: opID(3), Kind: "ayah_understood", Body: json.RawMessage(`{"ayah_ids":[115001],"understood_at":"2026-03-01T12:00:00Z"}`)},
		op(opID(4), "ayah_understood", map[string]any{"ayah_ids": []int{96001}, "understood_at": noon}),
	)

	for _, bad := range []int{1, 2, 3} {
		if got := results[opID(bad)]; got.Status != store.OpRefused {
			t.Fatalf("op %d came back %+v, so the device will resend it forever", bad, got)
		}
	}
	if results[opID(4)].Status != store.OpApplied {
		t.Fatalf("the good op behind three bad ones came back %+v", results[opID(4)])
	}

	// A body that is not a batch at all is the one thing refused whole — the
	// device has nothing per-op to be told about.
	if code := h.post(t, "/v1/sync", token, "not a batch").Code; code != http.StatusBadRequest {
		t.Fatalf("an unreadable batch answered %d", code)
	}
}

// The failure: a cursor the device made up, or one left over from a server
// that issued a different shape, silently reads as "the beginning" and the
// reader's whole history arrives as new.
func TestACursorThisServerNeverIssuedIsRefusedRatherThanReadAsTheBeginning(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-bad-cursor")

	for _, cursor := range []string{"lastweek", "42", "2026-03-01T12:00:00Z"} {
		if code := h.get(t, "/v1/changes?since="+cursor, token).Code; code != http.StatusBadRequest {
			t.Errorf("cursor %q answered %d, expected 400", cursor, code)
		}
	}
}

func change(page store.Changes, id string) (store.Change, bool) {
	for _, c := range page.Changes {
		if c.ID == id {
			return c, true
		}
	}
	return store.Change{}, false
}

func holds(page store.Changes, id string) bool {
	_, found := change(page, id)
	return found
}
