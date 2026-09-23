package store_test

import (
	"encoding/json"
	"os"
	"slices"
	"sort"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// contractPath is the second file both halves answer to, beside the set id
// vectors. The device suite reads these same rows from
// app/test/data/sync_contract_vectors_test.dart. Neither suite computes what
// it asserts, so the two cannot agree with themselves while disagreeing with
// each other — which is exactly how the set id shipped wrong.
const contractPath = "../../../docs/adr/0002-sync-contract-vectors.json"

type opBodyVector struct {
	Kind  string          `json:"kind"`
	Label string          `json:"label"`
	Body  json.RawMessage `json:"body"`
}

type opResultVector struct {
	Status    string `json:"status"`
	Landed    bool   `json:"landed"`
	Permanent bool   `json:"permanent"`
	Label     string `json:"label"`
}

type changeKindVector struct {
	Kind string                     `json:"kind"`
	Row  map[string]json.RawMessage `json:"row"`
}

type syncContract struct {
	OpBodies struct {
		Vectors []opBodyVector `json:"vectors"`
	} `json:"op_bodies"`
	OpResults struct {
		Vectors []opResultVector `json:"vectors"`
	} `json:"op_results"`
	ChangeKinds struct {
		Vectors []changeKindVector `json:"vectors"`
	} `json:"change_kinds"`
	ReadingOrders struct {
		Vectors []string `json:"vectors"`
		NotOne  string   `json:"not_a_reading_order"`
	} `json:"reading_orders"`
}

func contract(t *testing.T) syncContract {
	t.Helper()
	raw, err := os.ReadFile(contractPath)
	if err != nil {
		t.Fatalf("the shared sync contract is unreadable, so nothing checks the server against the device: %v", err)
	}
	var c syncContract
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatalf("the shared sync contract is not readable as vectors: %v", err)
	}
	if len(c.OpBodies.Vectors) == 0 || len(c.OpResults.Vectors) == 0 ||
		len(c.ChangeKinds.Vectors) == 0 || len(c.ReadingOrders.Vectors) == 0 {
		t.Fatal("a section of the shared contract is empty, so this file passes without checking anything")
	}
	return c
}

// The failure: a field is renamed on one side, the decoder rejects the whole
// body because it disallows unknown fields, and the refusal is permanent — so
// the reader's prayer, note or understood aya is dead-lettered and never
// arrives. The bodies here are the device's own, checked in rather than built
// from these structs, so this reddens the moment the server stops answering
// to what the device actually sends.
func TestEveryOpBodyADeviceSendsIsAcceptedRatherThanRefusedForever(t *testing.T) {
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-op-bodies")

	for i, v := range contract(t).OpBodies.Vectors {
		op := store.Op{ClientOpID: opID(700 + i), Kind: v.Kind, Body: v.Body}
		results, err := db.Apply(t.Context(), user, []store.Op{op})
		if err != nil {
			t.Fatalf("%s (%s): %v", v.Kind, v.Label, err)
		}
		if results[0].Status != store.OpApplied {
			t.Errorf("%s (%s) came back %q: %s — the device spells this body one way and the server another, so the write is lost for good",
				v.Kind, v.Label, results[0].Status, results[0].Reason)
		}
	}
}

// The failure: a status word is renamed on the server, and the device reads
// the new word as transient — so it retries a write that can never land until
// the budget runs out, or parks one that could have landed. Both suites stay
// green, because each asserts against its own spelling.
func TestTheServerSpeaksTheOpOutcomeWordsTheDeviceParksAndRetriesOn(t *testing.T) {
	c := contract(t)
	byStatus := map[string]opResultVector{}
	for _, v := range c.OpResults.Vectors {
		byStatus[v.Status] = v
	}
	for word, constant := range map[string]string{
		"applied":   store.OpApplied,
		"duplicate": store.OpDuplicate,
		"refused":   store.OpRefused,
		"failed":    store.OpFailed,
	} {
		if _, ok := byStatus[constant]; !ok {
			t.Fatalf("the server answers %q where the shared contract knows only %v, and the device treats a word it has never heard of as worth retrying forever",
				constant, keys(byStatus))
		}
		if constant != word {
			t.Fatalf("the server answers %q where the contract names it %q", constant, word)
		}
	}

	// And the server really produces them. A word that is only a constant is
	// a word nothing checks.
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-outcomes")
	bodies := contract(t).OpBodies.Vectors
	first := store.Op{ClientOpID: opID(720), Kind: bodies[0].Kind, Body: bodies[0].Body}

	if got := status(t, db, user, first); got != store.OpApplied {
		t.Fatalf("a fresh write came back %q, not the contract's applied", got)
	}
	if got := status(t, db, user, first); got != store.OpDuplicate {
		t.Fatalf("a replayed write came back %q, not the contract's duplicate", got)
	}
	bad := store.Op{ClientOpID: opID(721), Kind: "ayah_understood", Body: json.RawMessage(`{"nope":1}`)}
	if got := status(t, db, user, bad); got != store.OpRefused {
		t.Fatalf("a body the decoder cannot read came back %q, not the contract's refused — the device will retry it until its budget runs out", got)
	}
}

// The failure: the server renames a kind, and the device's apply falls through
// to a default arm that returns zero. The device stops writing that table
// entirely and neither side raises anything. The kinds and their row keys are
// checked in, so a rename here has to be a rename there.
func TestTheChangeStreamEmitsOnlyTheKindsAndRowKeysTheDeviceKnowsHowToApply(t *testing.T) {
	c := contract(t)
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-kinds")

	// One row in every table the stream reads from, through the real ops.
	for i, v := range c.OpBodies.Vectors {
		if got := status(t, db, user, store.Op{ClientOpID: opID(740 + i), Kind: v.Kind, Body: v.Body}); got != store.OpApplied {
			t.Fatalf("seeding %s came back %q", v.Kind, got)
		}
	}

	page := pull(t, db, user, "")
	seen := map[string]json.RawMessage{}
	for _, change := range page.Changes {
		seen[change.Kind] = change.Row
	}
	want := map[string]bool{}
	for _, v := range c.ChangeKinds.Vectors {
		want[v.Kind] = true
		row, ok := seen[v.Kind]
		if !ok {
			t.Errorf("the stream carried no %q row, though the contract says the device applies one — either this kind is gone or nothing exercises it", v.Kind)
			continue
		}
		var got map[string]json.RawMessage
		if err := json.Unmarshal(row, &got); err != nil {
			t.Fatalf("%s row: %v", v.Kind, err)
		}
		if a, b := keys(got), keys(v.Row); !slices.Equal(a, b) {
			t.Errorf("the server builds a %s row out of %v where the device reads %v, so the device applies a row with fields missing", v.Kind, a, b)
		}
	}
	for kind := range seen {
		if !want[kind] {
			t.Errorf("the stream carries a %q the device has never heard of, and the device applies none of it", kind)
		}
	}
}

// The failure: a reading order the device cannot spell reaches the server,
// which stores it, derives a set id from it, and hands back a set no device
// recognises. The words are half of what names a set, so they are checked
// against the shared list rather than left to a column constraint.
func TestOnlyTheTwoReadingOrderWordsTheDeviceHasAreAccepted(t *testing.T) {
	c := contract(t)
	db, _ := testenv.Postgres(t)
	user := reader(t, db, "sub-orders")

	for i, order := range c.ReadingOrders.Vectors {
		op := prayedOp(opID(760+i), order, 1001, 1007, time.Now())
		if got := status(t, db, user, op); got != store.OpApplied {
			t.Errorf("the server refused %q, which is a word the device can and does send, so that reader's prayer is dead-lettered", order)
		}
	}

	stray := prayedOp(opID(780), c.ReadingOrders.NotOne, 1001, 1007, time.Now())
	if got := status(t, db, user, stray); got != store.OpRefused {
		t.Errorf("the server answered %q to reading order %q, so a set no device can name is now in the reader's history",
			got, c.ReadingOrders.NotOne)
	}
}

// status is land's cousin for the tests that are about the answer itself
// rather than about the write landing.
func status(t *testing.T, db *store.Store, user string, op store.Op) string {
	t.Helper()
	results, err := db.Apply(t.Context(), user, []store.Op{op})
	if err != nil {
		t.Fatalf("flush %s: %v", op.ClientOpID, err)
	}
	return results[0].Status
}

func prayedOp(clientOpID, readingOrder string, start, end int, at time.Time) store.Op {
	body, _ := json.Marshal(map[string]any{
		"set_id":        store.SetID(readingOrder, start, end),
		"start_ayah_id": start,
		"end_ayah_id":   end,
		"reading_order": readingOrder,
		"prayed_at":     at,
	})
	return store.Op{ClientOpID: clientOpID, Kind: "set_prayed", Body: body}
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
