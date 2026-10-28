package store_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// Each way an op can be turned away names its own key, and its reason keeps
// the words installed apps already parse (app/lib/data/outbox.dart). The
// decoder's own text never reaches the device: it names Go types.
func TestAnOpVerdictNamesTheKeyAClientBranchesOn(t *testing.T) {
	db, pool := testenv.Postgres(t)
	me, err := db.ReaderFor(t.Context(), "sub-opkeys", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	apply := func(user, kind, body string) store.OpResult {
		t.Helper()
		res, err := db.Apply(t.Context(), user, []store.Op{{ClientOpID: uuid.NewString(), Kind: kind, Body: json.RawMessage(body)}})
		if err != nil || len(res) != 1 {
			t.Fatalf("apply %s: %v %v", kind, res, err)
		}
		return res[0]
	}
	rename := func(from, to string) {
		t.Helper()
		if _, err := pool.Exec(t.Context(), `ALTER TABLE `+from+` RENAME TO `+to); err != nil {
			t.Fatal(err)
		}
	}

	for _, c := range []struct {
		name, user, kind, body string
		status, key, reason    string
		broken                 string // a table renamed away for the op
	}{
		{"unknown kind", me.ID, "nope", `{}`, store.OpRefused, "op.unknown_kind", `unknown kind "nope"`, ""},
		{"no colon in the reason", me.ID, "ayah_understood", `{"ayah_ids":[]}`, store.OpRefused, "op.bad_value", "no ayas to mark", ""},
		{"decoder refuses", me.ID, "ayah_understood", `{"x":1}`, store.OpRefused, "op.bad_body", "the op body is not shaped like this kind", ""},
		{"no such kept item", me.ID, "kept_delete", `{"id":"7f1c3e2a-0000-4000-8000-0000000000aa","deleted_at":"2026-01-01T00:00:00Z"}`, store.OpRefused, "op.not_found", "no kept item 7f1c3e2a-0000-4000-8000-0000000000aa", ""},
		{"pg class 22", me.ID, "kept_delete", `{"id":"x","deleted_at":"2026-01-01T00:00:00Z"}`, store.OpRefused, "op.bad_body", "the op body is not shaped like this kind", ""},
		{"pg 23503", "00000000-0000-4000-8000-0000000000ff", "ayah_understood", `{"ayah_ids":[1001]}`, store.OpRefused, "op.not_found", "it refers to something that is not here", ""},
		{"pg other 23", me.ID, "set_recorded", `{"id":"7f1c3e2a-0000-4000-8000-000000000001","start_ayah_id":1001,"end_ayah_id":1007,"reading_order":"x","created_at":"2026-01-01T00:00:00Z"}`, store.OpRefused, "op.conflict", "it does not fit what is already recorded", ""},
		{"server fails", me.ID, "ayah_understood", `{"ayah_ids":[1001]}`, store.OpFailed, "op.retry", "not applied, try again", "ayah_understood"},
	} {
		t.Run(c.name, func(t *testing.T) {
			if c.broken != "" {
				rename(c.broken, c.broken+"_away")
				defer rename(c.broken+"_away", c.broken)
			}
			got := apply(c.user, c.kind, c.body)
			if got.Status != c.status || string(got.Key) != c.key || got.Reason != c.reason {
				t.Errorf("got %s %s %q, want %s %s %q", got.Status, got.Key, got.Reason, c.status, c.key, c.reason)
			}
		})
	}
}
