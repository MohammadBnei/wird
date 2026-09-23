package api_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"testing"
	"time"
)

// The end-to-end gate: a real server on a real socket, a real
// Postgres behind it, and the real Dart client driven against it. A second
// socket lets the test make the real server genuinely fail — the table the
// write needs goes away — so a "failed" verdict is the server's own answer to
// a real fault rather than a string a fake was told to say.
func TestGateEndToEndWithTheRealClient(t *testing.T) {
	h := newHarness(t)
	server := httptest.NewServer(h.routes)
	defer server.Close()

	control := http.NewServeMux()
	exec1 := func(w http.ResponseWriter, sql string) {
		if _, err := h.pool.Exec(t.Context(), sql); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}
	control.HandleFunc("POST /break", func(w http.ResponseWriter, _ *http.Request) {
		exec1(w, `ALTER TABLE ayah_understood RENAME TO ayah_understood_away`)
	})
	control.HandleFunc("POST /mend", func(w http.ResponseWriter, _ *http.Request) {
		exec1(w, `ALTER TABLE ayah_understood_away RENAME TO ayah_understood`)
	})
	knobs := httptest.NewServer(control)
	defer knobs.Close()

	token := h.issuer.Token(t, "sub-gate-e2e", audience, time.Hour)

	cmd := exec.Command("fvm", "flutter", "test", "e2e/gate_e2e_test.dart",
		"--dart-define=WIRD_E2E_URL="+server.URL,
		"--dart-define=WIRD_E2E_KNOBS="+knobs.URL,
		"--dart-define=WIRD_E2E_TOKEN="+token)
	cmd.Dir = "../../../app"
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("the real client against the real server: %v", err)
	}
}
