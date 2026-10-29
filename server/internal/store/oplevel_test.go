package store

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"testing"
)

// A reader whose phone drops mid-sync cancels the context, and every op left
// fails with context.Canceled: that must not count toward log-error-rate-spike.
// Any other failure is ours, and stays ERROR.
func TestFailedOpIsWarnWhenTheReaderWentAway(t *testing.T) {
	for _, c := range []struct {
		err  error
		want slog.Level
	}{
		{fmt.Errorf("begin: %w", context.Canceled), slog.LevelWarn},
		{errors.New("connection reset"), slog.LevelError},
		{context.DeadlineExceeded, slog.LevelError},
	} {
		if got := failedLevel(c.err); got != c.want {
			t.Errorf("%v: %s, want %s", c.err, got, c.want)
		}
	}
}
