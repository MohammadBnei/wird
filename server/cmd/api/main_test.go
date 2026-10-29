package main

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// A sweep in flight when SIGTERM lands has to commit: work gets a context the
// signal does not cancel, and the loop itself stops at the signal.
// Mutation: every passing ctx to work instead of WithoutCancel(ctx) fails the
// "cancelled under it" check.
func TestEveryStopsAtTheSignalButNotTheWorkInFlight(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	got := make(chan context.Context)
	release := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		every(ctx, time.Hour, func(work context.Context) {
			got <- work
			<-release
		})
	}()

	// Positive control: work runs at once, on a live context.
	var work context.Context
	select {
	case work = <-got:
	case <-time.After(5 * time.Second):
		t.Fatal("work did not run at start")
	}
	if work.Err() != nil {
		t.Fatalf("work started on a cancelled context: %v", work.Err())
	}

	cancel()
	if work.Err() != nil {
		t.Errorf("the signal cancelled the work in flight under it: %v", work.Err())
	}
	close(release)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("every did not return after cancel")
	}
}

// The whole main, as Kubernetes stops it: SIGTERM once it is listening, then
// exit 0 with "wird-api drained" and no ERROR line.
func TestMainDrainsOnSIGTERM(t *testing.T) {
	if os.Getenv("WIRD_API_TEST_CHILD") == "1" {
		main()
		return
	}
	_, pool := testenv.Postgres(t)
	issuer := testenv.NewIssuer(t)

	cmd := exec.Command(os.Args[0], "-test.run=^TestMainDrainsOnSIGTERM$")
	cmd.Env = append(os.Environ(),
		"WIRD_API_TEST_CHILD=1",
		"WIRD_DEV=",
		"DATABASE_URL="+pool.Config().ConnString(),
		"OIDC_ISSUER="+issuer.URL,
		"OIDC_AUDIENCE=wird",
		"API_ADDR=127.0.0.1:0",
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill() })

	lines := make(chan string)
	go func() {
		defer close(lines)
		scan := bufio.NewScanner(stdout)
		for scan.Scan() {
			lines <- scan.Text()
		}
	}()

	var out []string
	timeout := time.After(30 * time.Second)
	signalled := false
	for line, ok := "", true; ok; {
		select {
		case line, ok = <-lines:
			if !ok {
				break
			}
			out = append(out, line)
			if !signalled && strings.Contains(line, `"msg":"wird-api listening"`) {
				signalled = true
				if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
					t.Fatal(err)
				}
			}
		case <-timeout:
			t.Fatalf("no exit within 30s:\n%s", strings.Join(out, "\n"))
		}
	}
	if err := cmd.Wait(); err != nil {
		t.Errorf("exit: %v, want 0:\n%s", err, strings.Join(out, "\n"))
	}
	all := strings.Join(out, "\n")
	if !signalled {
		t.Fatalf("never listened:\n%s", all)
	}
	if !strings.Contains(all, `"msg":"wird-api drained"`) {
		t.Errorf("no drained line:\n%s", all)
	}
	if strings.Contains(all, `"level":"ERROR"`) {
		t.Errorf("an ERROR on a clean SIGTERM:\n%s", all)
	}
}
