// Command api serves Wird user state to the Flutter client.
package main

import (
	"context"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/MohammadBnei/ukubi-go/telemetry"

	"github.com/MohammadBnei/wird/server/internal/api"
	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	slog.SetDefault(telemetry.NewLogger(os.Stdout))
	os.Exit(run(slog.Default()))
}

// run is main with an exit code, so the deferred db.Close runs before the
// process exits.
func run(log *slog.Logger) int {
	// SIGTERM is how Kubernetes stops a pod: it cancels ctx, the server drains
	// and the maintenance loops stop. A second signal kills at once (stop).
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() { <-ctx.Done(); stop() }()

	// Every problem with the configuration at once, before anything is opened:
	// a deployment missing a value never starts half-configured.
	cfg, err := fromProcess()
	if err != nil {
		log.Error("config refused", "err", err)
		return 1
	}

	// Before the database: deferred first, Shutdown runs last, once Serve has
	// drained and db.Close is done, so a hung collector never holds the
	// database open. Inert when cfg.Traces is empty (docs/adr/0040).
	tel, err := telemetry.New(cfg.Traces, "wird-api")
	if err != nil {
		log.Error("tracing unavailable", "err", err)
		return 1
	}
	defer func() {
		if err := tel.Shutdown(); err != nil {
			log.Warn("traces", "err", err)
		}
	}()

	// Startup runs to the end even after a SIGTERM, and Serve then drains at
	// once: a migration or discovery cancelled halfway would log a false ERROR.
	start := context.WithoutCancel(ctx)

	db, err := store.Open(start, cfg.DatabaseURL)
	if err != nil {
		log.Error("database unavailable", "err", err)
		return 1
	}
	defer db.Close()

	// The issuer and audience are the whole difference between the local stub
	// and authentik.bnei.dev. Nothing below this line knows which it is.
	issuer := cfg.OIDCIssuer
	authenticator, err := auth.New(start, issuer, cfg.OIDCAudience, db, log)
	if err != nil {
		log.Error("issuer unavailable", "issuer", issuer, "err", err)
		return 1
	}

	// Bind before announcing it, and before the loops start: a port already in
	// use logs only the listen error, and never exits mid-sweep.
	ln, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		log.Error("wird-api stopped", "err", err)
		return 1
	}

	var loops sync.WaitGroup
	loops.Go(func() { maintain(ctx, db, log) })
	loops.Go(func() { sweep(ctx, db, log) })
	// Before db.Close: a sweep in flight commits. stop first, or a Serve that
	// failed without a signal would wait on loops that never end.
	defer func() { stop(); loops.Wait() }()

	log.Info("wird-api listening", "addr", ln.Addr().String(), "issuer", issuer, "dev", cfg.Dev)
	if err := httpx.Serve(ctx, ln, api.Routes(db, authenticator, log, cfg.API, tel), log); err != nil {
		if ctx.Err() != nil {
			log.Error("wird-api shutdown failed", "err", err)
		} else {
			log.Error("wird-api stopped", "err", err)
		}
		return 1
	}
	log.Info("wird-api drained")
	return 0
}

// every runs work now and then once per interval until ctx is cancelled. The
// work itself runs on a context that SIGTERM does not cancel at once, so a
// sweep in flight commits rather than rolling back into a false ERROR. It is
// cancelled httpx.Drain after the signal: a prune stuck on a lock must not
// hold the exit past Kubernetes' grace, where SIGKILL skips db.Close.
func every(ctx context.Context, interval time.Duration, work func(context.Context)) {
	wctx, cancel := context.WithCancel(context.WithoutCancel(ctx))
	defer cancel()
	context.AfterFunc(ctx, func() { time.AfterFunc(httpx.Drain, cancel) })
	for ctx.Err() == nil {
		work(wctx)
		select {
		case <-ctx.Done():
		case <-time.After(interval):
		}
	}
}

// The op log is the one table that grows with every write a reader ever makes
// and nothing else prunes it.
//
// ponytail: a ticker in the process. Move it to a cron job if the API ever
// runs as more than one replica.
func maintain(ctx context.Context, db *store.Store, log *slog.Logger) {
	every(ctx, 24*time.Hour, func(ctx context.Context) {
		dropped, err := db.PruneOpLog(ctx)
		if err != nil {
			log.Error("op log prune", "err", err)
		} else if dropped > 0 {
			log.Info("op log pruned", "rows", dropped)
		}
	})
}

// sweepInterval is the only clock a report is ever written on, and it is two
// things at once. It is how long a reader waits to be read: a report is not in
// the operations view until a sweep puts it there. And it is how long a report
// sits in report_inbox carrying its author's transaction id, which is the one
// window docs/adr/0004 leaves open. Ten minutes is short enough that an
// operator reading a bug report is reading today's, and short enough that the
// window is not a working day wide.
//
// What the interval is not is a way of hiding the sweep: it ticks whether or
// not a report arrived, so its transaction id says the time of day and nothing
// about whether anybody reported.
const sweepInterval = 10 * time.Minute

// sweep is the write that belongs to the schedule rather than to a reader: it
// empties report_inbox into reports under a transaction id no reader's session
// caused.
//
// ponytail: a ticker in the process, and the sweep rewrites the whole table,
// so two of these racing could lose or double a report. Move it to a cron job
// if the API ever runs as more than one replica, the same as the prune above.
func sweep(ctx context.Context, db *store.Store, log *slog.Logger) {
	every(ctx, sweepInterval, func(ctx context.Context) {
		if err := db.SweepReports(ctx); err != nil {
			log.Error("report sweep", "err", err)
		}
	})
}
