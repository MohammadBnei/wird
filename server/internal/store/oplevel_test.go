package store

import (
	"context"
	"log/slog"
	"testing"
)

// A reader whose phone drops mid-sync cancels the request's context, and the
// op left fails with whatever the driver makes of the cut, which need not wrap
// context.Canceled: that must not count toward log-error-rate-spike. A failure
// under a live request is ours, and stays ERROR.
func TestFailedOpIsWarnWhenTheReaderWentAway(t *testing.T) {
	gone, cancel := context.WithCancel(context.Background())
	cancel()
	for _, c := range []struct {
		name string
		ctx  context.Context
		want slog.Level
	}{
		{"reader gone", gone, slog.LevelWarn},
		{"reader still there", context.Background(), slog.LevelError},
	} {
		if got := failedLevel(c.ctx); got != c.want {
			t.Errorf("%s: %s, want %s", c.name, got, c.want)
		}
	}
}
