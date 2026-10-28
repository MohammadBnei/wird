package api_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/api"
)

// Every error wird-api answers is ukubi-go's body: a code with its status, a
// key from internal/keys for a client to branch on, and the words a person
// reads, which are the words each site said before keys (docs/adr/0038).
func TestEveryErrorCarriesItsKey(t *testing.T) {
	h := newHarness(t)
	tok := h.tokenFor(t, "sub-keys")
	post := func(path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+tok)
		return h.serve(r)
	}
	rename := func(from, to string) {
		t.Helper()
		if _, err := h.pool.Exec(t.Context(), `ALTER TABLE `+from+` RENAME TO `+to); err != nil {
			t.Fatal(err)
		}
	}
	gone := h.issuer.Token(t, "sub-gone", audience, time.Hour, map[string]any{"auth_time": time.Now().Add(-time.Hour).Unix()})
	if w := h.serve(h.request(t, http.MethodDelete, "/v1/me", gone)); w.Code != http.StatusNoContent {
		t.Fatalf("delete me: %d %s", w.Code, w.Body)
	}
	var many []string
	for i := range 501 {
		many = append(many, fmt.Sprintf(`{"client_op_id":"op-%d","kind":"x","body":{}}`, i))
	}
	noStore := func(method string) func() *httptest.ResponseRecorder {
		return func() *httptest.ResponseRecorder { return h.serve(h.request(t, method, "/download/android", "")) }
	}
	bad := newHarnessWith(t, api.Config{Models: &api.Models{Bucket: "b", Endpoint: "%zz"}, APKKey: "android/wird-x.apk"})
	unsigned := func(method, path string) func() *httptest.ResponseRecorder {
		return func() *httptest.ResponseRecorder { return bad.serve(bad.request(t, method, path, "")) }
	}
	broken := func(table string, do func() *httptest.ResponseRecorder) func() *httptest.ResponseRecorder {
		return func() *httptest.ResponseRecorder {
			rename(table, table+"_away")
			defer rename(table+"_away", table)
			return do()
		}
	}
	get := func(path, token string) func() *httptest.ResponseRecorder {
		return func() *httptest.ResponseRecorder { return h.get(t, path, token) }
	}

	for _, c := range []struct {
		site               string
		do                 func() *httptest.ResponseRecorder
		status             int
		code, key, message string
	}{
		{"no bearer", get("/v1/me", ""), 401, "unauthenticated", "auth.token_missing", "a bearer token is required"},
		{"wrong audience", get("/v1/me", h.issuer.Token(t, "sub-x", "other-app", time.Hour)), 401, "unauthenticated", "auth.token_rejected", "token rejected"},
		{"empty subject", get("/v1/me", h.issuer.Token(t, "", audience, time.Hour)), 401, "unauthenticated", "auth.token_rejected", "token rejected"},
		{"deleted reader", get("/v1/me", gone), 401, "unauthenticated", "auth.token_rejected", "token rejected"},
		{"reader lookup fails", broken("users", get("/v1/me", tok)), 500, "internal", "internal", "unavailable"},
		{"unreadable batch", func() *httptest.ResponseRecorder { return post("/v1/sync", "{") }, 400, "invalid_argument", "request.bad_batch", "the batch is not readable"},
		{"501 ops", func() *httptest.ResponseRecorder { return post("/v1/sync", `{"ops":[`+strings.Join(many, ",")+`]}`) }, 400, "invalid_argument", "request.batch_too_big", "too many ops in one batch"},
		{"bad cursor", get("/v1/changes?since=garbage", tok), 400, "invalid_argument", "request.bad_cursor", "that is not a cursor this server issued"},
		{"bad kind", get("/v1/kept?kind=x", tok), 400, "invalid_argument", "request.bad_kind", "kind must be aya, root or note"},
		{"bad root", get("/v1/roots/abc/lexicon", tok), 400, "invalid_argument", "request.bad_root", "letters must be the joined Arabic form of a root"},
		{"no such aya", get("/v1/ayahs/115/1/tafsir", tok), 400, "invalid_argument", "request.bad_ayah", "no such aya"},
		{"nothing yet", get("/v1/ayahs/2/255/tafsir", tok), 404, "not_found", "store.not_found", "nothing here yet"},
		{"store fails", broken("tafsir_entries", get("/v1/ayahs/2/255/tafsir", tok)), 500, "internal", "internal", "unavailable"},
		{"senses fail", broken("root_senses", get("/v1/senses", "")), 500, "internal", "internal", "unavailable"},
		{"no recogniser", get("/models/base/x.onnx", ""), 503, "unavailable", "models.not_published", "no recogniser is published here"},
		{"no apk GET", noStore(http.MethodGet), 503, "unavailable", "apk.not_published", "no Android build is published here yet"},
		{"no apk HEAD", noStore(http.MethodHead), 503, "unavailable", "apk.not_published", "no Android build is published here yet"},
		// Not 503: the site's Download toast reads 503 as "not published yet"
		// (site/README.md), and a presign failure is this server misconfigured.
		{"recogniser unsigned", unsigned(http.MethodGet, "/models/base/x.onnx"), 500, "internal", "models.unreachable", "the recogniser cannot be reached"},
		{"apk unsigned GET", unsigned(http.MethodGet, "/download/android"), 500, "internal", "apk.unreachable", "the Android build cannot be reached"},
		{"apk unsigned HEAD", unsigned(http.MethodHead, "/download/android"), 500, "internal", "apk.unreachable", "the Android build cannot be reached"},
	} {
		t.Run(c.site, func(t *testing.T) {
			w := c.do()
			if w.Code != c.status || w.Header().Get("Content-Type") != "application/json" {
				t.Fatalf("got %d %q, want %d application/json", w.Code, w.Header().Get("Content-Type"), c.status)
			}
			var body map[string]string
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatalf("body %q: %v", w.Body, err)
			}
			want := map[string]string{"code": c.code, "key": c.key, "message": c.message, "source": "", "detail": ""}
			if fmt.Sprint(body) != fmt.Sprint(want) {
				t.Errorf("body %v, want %v", body, want)
			}
		})
	}

	// An op's verdict carries its key on the wire beside the reason.
	w := post("/v1/sync", `{"ops":[{"client_op_id":"aaaaaaaa-0000-4000-8000-000000000001","kind":"nope","body":{}}]}`)
	var got struct {
		Results []map[string]string `json:"results"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil || len(got.Results) != 1 {
		t.Fatalf("sync: %d %s %v", w.Code, w.Body, err)
	}
	if r := got.Results[0]; r["key"] != "op.unknown_kind" || r["reason"] != `unknown kind "nope"` {
		t.Errorf("op result %v", r)
	}
}
