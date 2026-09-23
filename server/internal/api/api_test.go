package api_test

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/api"
	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

const audience = "wird"

type harness struct {
	routes http.Handler
	issuer *testenv.Issuer
	db     *store.Store
	pool   *pgxpool.Pool
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	db, pool := testenv.Postgres(t)
	issuer := testenv.NewIssuer(t)
	authenticator, err := auth.New(t.Context(), issuer.URL, audience, db, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatalf("issuer discovery: %v", err)
	}
	return &harness{routes: api.Routes(db, authenticator, slog.New(slog.DiscardHandler)), issuer: issuer, db: db, pool: pool}
}

// get sends a request carrying token, or none at all when token is empty.
func (h *harness) get(t *testing.T, path, token string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.routes.ServeHTTP(w, r)
	return w
}

func (h *harness) tokenFor(t *testing.T, subject string) string {
	t.Helper()
	return h.issuer.Token(t, subject, audience, time.Hour)
}

func (h *harness) readers(t *testing.T) int {
	t.Helper()
	var n int
	if err := h.pool.QueryRow(t.Context(), `SELECT count(*) FROM users`).Scan(&n); err != nil {
		t.Fatalf("count readers: %v", err)
	}
	return n
}

// Each row is a way somebody reads a stranger's prayers, or reads them after
// they should have been locked out. All three must end at the door.
func TestNoUnprovenTokenReachesAReadersState(t *testing.T) {
	h := newHarness(t)
	elsewhere := testenv.NewIssuer(t)

	refusals := []struct {
		breach string
		token  string
	}{
		{"no token at all, which is the open internet asking for a reader's prayers",
			""},
		{"an expired token, so a signed-out phone keeps reading the account",
			h.issuer.Token(t, "sub-expired", audience, -time.Minute)},
		{"a token minted by an issuer we never trusted, which would let anyone forge a subject",
			elsewhere.Token(t, "sub-forged", audience, time.Hour)},
		{"a token issued for a different application, replayed at us",
			h.issuer.Token(t, "sub-elsewhere", "some-other-app", time.Hour)},
		{"a token whose signature has been swapped for another key's",
			h.issuer.Token(t, "sub-tampered", audience, time.Hour) + "x"},
	}

	for _, r := range refusals {
		for _, path := range []string{"/v1/me", "/v1/progress", "/v1/kept", "/v1/corpus/version"} {
			got := h.get(t, path, r.token).Code
			if got != http.StatusUnauthorized {
				t.Errorf("%s: GET %s answered %d, expected 401", r.breach, path, got)
			}
		}
	}

	if n := h.readers(t); n != 0 {
		t.Fatalf("%d reader rows were minted from tokens nobody verified", n)
	}
}

func TestFirstSignInMintsTheReaderAndReturningDoesNotMintASecond(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-first")

	var first store.User
	decode(t, h.get(t, "/v1/me", token), http.StatusOK, &first)
	if first.OIDCSubject != "sub-first" || first.ID == "" {
		t.Fatalf("me answered %+v", first)
	}

	var again store.User
	decode(t, h.get(t, "/v1/me", token), http.StatusOK, &again)
	if again.ID != first.ID {
		t.Fatalf("a second sign-in made a second reader: %s then %s", first.ID, again.ID)
	}
	if n := h.readers(t); n != 1 {
		t.Fatalf("%d readers exist after one person signed in twice", n)
	}
}

func TestTheClientCanReadTheCorpusVersionItRefusesToSyncAcross(t *testing.T) {
	h := newHarness(t)

	var version store.CorpusVersion
	decode(t, h.get(t, "/v1/corpus/version", h.tokenFor(t, "sub-version")), http.StatusOK, &version)
	if version.CorpusVersion < 1 {
		t.Fatalf("no corpus version to negotiate against: %+v", version)
	}
	if version.BuiltAt.IsZero() {
		t.Fatal("the version carries no build time, so a stale server looks current")
	}
}

func TestASecondDeviceReadsTheSameProgressWithoutStoringACount(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-tablet")

	var me store.User
	decode(t, h.get(t, "/v1/me", token), http.StatusOK, &me)
	seed(t, h.pool, `INSERT INTO ayah_understood (id, user_id, ayah_id)
	                 VALUES (gen_random_uuid(), $1, 2142), (gen_random_uuid(), $1, 78001)`, me.ID)
	seed(t, h.pool, `INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order)
	                 VALUES (gen_random_uuid(), $1, 1, 96001, 96005, 'nuzul')`, me.ID)

	var p store.Progress
	decode(t, h.get(t, "/v1/progress", token), http.StatusOK, &p)
	if p.Understood != 2 {
		t.Fatalf("the tablet sees %d ayas understood, the phone marked 2", p.Understood)
	}
	if p.JuzUnderstood[1] != 1 || p.JuzUnderstood[29] != 1 {
		t.Fatalf("the juz ring would be drawn from %v", p.JuzUnderstood)
	}
	if p.PrayersPerSet == nil || *p.PrayersPerSet != 0 {
		t.Fatalf("a set studied but not yet prayed gives ratio %v, expected 0", p.PrayersPerSet)
	}
}

func TestOneReadersKeptListIsNeverAnothersAndTheFilterIsChecked(t *testing.T) {
	h := newHarness(t)
	mine := h.tokenFor(t, "sub-keeper")
	theirs := h.tokenFor(t, "sub-stranger")

	var me store.User
	decode(t, h.get(t, "/v1/me", mine), http.StatusOK, &me)
	seed(t, h.pool, `INSERT INTO kept_items (id, user_id, kind, body, created_at, updated_at)
	                 VALUES (gen_random_uuid(), $1, 'note', 'mine alone', now(), now())`, me.ID)

	var list struct{ Items []store.KeptItem }
	decode(t, h.get(t, "/v1/kept", mine), http.StatusOK, &list)
	if len(list.Items) != 1 || list.Items[0].Body != "mine alone" {
		t.Fatalf("the keeper's own list came back as %+v", list.Items)
	}

	var stranger struct{ Items []store.KeptItem }
	decode(t, h.get(t, "/v1/kept", theirs), http.StatusOK, &stranger)
	if len(stranger.Items) != 0 {
		t.Fatalf("a stranger read somebody else's notes: %+v", stranger.Items)
	}

	if code := h.get(t, "/v1/kept?kind=everything", mine).Code; code != http.StatusBadRequest {
		t.Fatalf("an unknown kind answered %d instead of being refused", code)
	}
}

func TestAnAyaNobodyHasLicensedProseForIsEmptyRatherThanInvented(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-reader")

	for _, path := range []string{
		"/v1/ayahs/2/255/tafsir",
		"/v1/ayahs/2/255/irab",
		"/v1/roots/" + url.PathEscape("كتب") + "/lexicon",
	} {
		if code := h.get(t, path, token).Code; code != http.StatusNotFound {
			t.Errorf("GET %s answered %d; unsourced prose must be absent, never improvised", path, code)
		}
	}
}

func TestSeededProseArrivesFlaggedSoNoReaderMistakesItForScholarship(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-studier")

	var tafsir struct {
		AyahID  int                 `json:"ayah_id"`
		Entries []store.TafsirEntry `json:"entries"`
	}
	decode(t, h.get(t, "/v1/ayahs/103/3/tafsir", token), http.StatusOK, &tafsir)
	if tafsir.AyahID != 103003 || len(tafsir.Entries) == 0 {
		t.Fatalf("tafsir for 103:3 came back as %+v", tafsir)
	}
	for _, e := range tafsir.Entries {
		if !e.Placeholder {
			t.Errorf("tafsir by %q arrived unflagged, so the app would render it as sourced", e.Author)
		}
	}

	var irab struct {
		Entries []store.IrabEntry `json:"entries"`
	}
	decode(t, h.get(t, "/v1/ayahs/103/3/irab", token), http.StatusOK, &irab)
	for _, e := range irab.Entries {
		if !e.Placeholder {
			t.Errorf("the parsing of %q arrived unflagged", e.SegmentAr)
		}
	}

	var lexicon struct {
		RootLetters string               `json:"root_letters"`
		Entries     []store.LexiconEntry `json:"entries"`
	}
	decode(t, h.get(t, "/v1/roots/"+url.PathEscape("صبر")+"/lexicon", token), http.StatusOK, &lexicon)
	if lexicon.RootLetters != "صبر" || len(lexicon.Entries) != 2 {
		t.Fatalf("the lexicon for ص ب ر came back as %+v", lexicon)
	}
	for _, e := range lexicon.Entries {
		if !e.Placeholder {
			t.Errorf("%q arrived unflagged, so the app would print it as a quotation", e.Source)
		}
	}
}

func TestAReferenceToAnAyaThatDoesNotExistIsRefusedAtTheDoor(t *testing.T) {
	h := newHarness(t)
	token := h.tokenFor(t, "sub-typo")

	bad := []struct {
		why  string
		path string
	}{
		{"there is no 115th sūra", "/v1/ayahs/115/1/tafsir"},
		{"sūra numbering starts at one", "/v1/ayahs/0/1/irab"},
		{"aya numbering starts at one", "/v1/ayahs/2/0/tafsir"},
		{"a word where a number belongs", "/v1/ayahs/two/5/tafsir"},
		{"a latin string is not a root", "/v1/roots/sabr/lexicon"},
	}
	for _, c := range bad {
		if code := h.get(t, c.path, token).Code; code != http.StatusBadRequest {
			t.Errorf("%s: GET %s answered %d, expected 400", c.why, c.path, code)
		}
	}
}

func decode(t *testing.T, w *httptest.ResponseRecorder, want int, into any) {
	t.Helper()
	if w.Code != want {
		t.Fatalf("status %d, expected %d: %s", w.Code, want, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), into); err != nil {
		t.Fatalf("response body %q: %v", w.Body.String(), err)
	}
}

func seed(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	if _, err := pool.Exec(t.Context(), sql, args...); err != nil {
		t.Fatalf("seed: %v", err)
	}
}
