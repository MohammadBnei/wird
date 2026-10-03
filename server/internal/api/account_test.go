package api_test

import (
	"net/http"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/store"
)

// signedIn mints the reader behind subject, gives them a set, and returns the
// token they signed in with at the given moment.
func (h *harness) signedIn(t *testing.T, subject string, at time.Time) (string, store.User) {
	t.Helper()
	token := h.issuer.Token(t, subject, audience, time.Hour, map[string]any{"auth_time": at.Unix()})
	var me store.User
	decode(t, h.get(t, "/v1/me", token), http.StatusOK, &me)
	if _, err := h.pool.Exec(t.Context(), `
		INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order)
		VALUES (gen_random_uuid(), $1, 1, 1, 7, 'nuzul')`, me.ID); err != nil {
		t.Fatalf("seed a set: %v", err)
	}
	return token, me
}

func (h *harness) owned(t *testing.T) int {
	t.Helper()
	var n int
	if err := h.pool.QueryRow(t.Context(), `SELECT count(*) FROM sets`).Scan(&n); err != nil {
		t.Fatalf("count sets: %v", err)
	}
	return n
}

func TestADeletedAccountTakesEverythingItOwnedWithIt(t *testing.T) {
	h := newHarness(t)
	token, _ := h.signedIn(t, "sub-leaving", time.Now().Add(-time.Hour))
	h.signedIn(t, "sub-staying", time.Now().Add(-time.Hour))

	if got := h.serve(h.request(t, http.MethodDelete, "/v1/me", token)).Code; got != http.StatusNoContent {
		t.Fatalf("delete answered %d", got)
	}
	if n := h.readers(t); n != 1 {
		t.Fatalf("%d readers left, want only the one who stayed", n)
	}
	if n := h.owned(t); n != 1 {
		t.Fatalf("%d sets left, want only the stayer's: the leaver's state outlived their account", n)
	}
}

// Each row is a phone still holding a token from before the deletion. Any one
// of them reaching EnsureUser would mint the account back, and its outbox
// would refill it.
func TestATokenFromBeforeTheDeletionCannotBringTheAccountBack(t *testing.T) {
	h := newHarness(t)
	signedInAt := time.Now().Add(-time.Hour)
	token, _ := h.signedIn(t, "sub-gone", signedInAt)
	if got := h.serve(h.request(t, http.MethodDelete, "/v1/me", token)).Code; got != http.StatusNoContent {
		t.Fatalf("delete answered %d", got)
	}

	for _, c := range []struct {
		name  string
		token string
	}{
		{"the same token, on the phone that deleted", token},
		{"a refresh on a second device: new iat, the old sign-in's auth_time",
			h.issuer.Token(t, "sub-gone", audience, time.Hour, map[string]any{"auth_time": signedInAt.Unix()})},
		{"a token that never said when its sign-in was", h.tokenFor(t, "sub-gone")},
	} {
		if got := h.get(t, "/v1/me", c.token).Code; got != http.StatusUnauthorized {
			t.Errorf("%s: answered %d, want 401", c.name, got)
		}
	}
	if n := h.readers(t); n != 0 {
		t.Fatalf("%d readers exist after the only one deleted their account", n)
	}
}

func TestSigningInAgainAfterADeletionStartsAnEmptyAccount(t *testing.T) {
	h := newHarness(t)
	token, before := h.signedIn(t, "sub-back", time.Now().Add(-time.Hour))
	if got := h.serve(h.request(t, http.MethodDelete, "/v1/me", token)).Code; got != http.StatusNoContent {
		t.Fatalf("delete answered %d", got)
	}

	fresh := h.issuer.Token(t, "sub-back", audience, time.Hour, map[string]any{"auth_time": time.Now().Add(time.Second).Unix()})
	var after store.User
	decode(t, h.get(t, "/v1/me", fresh), http.StatusOK, &after)
	if after.ID == before.ID {
		t.Fatal("the new sign-in got the deleted account back")
	}
	if n := h.owned(t); n != 0 {
		t.Fatalf("the new account starts with %d sets", n)
	}
}
