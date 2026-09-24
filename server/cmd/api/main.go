// Command api serves Wird user state to the Flutter client.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/MohammadBnei/wird/server/internal/api"
	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	log := slog.Default()
	ctx := context.Background()

	db, err := store.Open(ctx, env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"))
	if err != nil {
		log.Error("database unavailable", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	// One variable is the whole difference between the local stub and
	// authentik.bnei.dev. Nothing below this line knows which it is.
	issuer := env("OIDC_ISSUER", "http://localhost:8082/wird")
	authenticator, err := auth.New(ctx, issuer, env("OIDC_AUDIENCE", "wird"), db, log)
	if err != nil {
		log.Error("issuer unavailable", "issuer", issuer, "err", err)
		os.Exit(1)
	}

	go maintain(ctx, db, log)
	go sweep(ctx, db, log)

	addr := env("API_ADDR", ":8080")
	log.Info("wird-api listening", "addr", addr, "issuer", issuer)
	if err := http.ListenAndServe(addr, api.Routes(db, authenticator, log)); err != nil {
		log.Error("wird-api stopped", "err", err)
		os.Exit(1)
	}
}

// The op log is the one table that grows with every write a reader ever makes
// and nothing else prunes it.
//
// ponytail: a ticker in the process. Move it to a cron job if the API ever
// runs as more than one replica.
func maintain(ctx context.Context, db *store.Store, log *slog.Logger) {
	for {
		dropped, err := db.PruneOpLog(ctx)
		if err != nil {
			log.Error("op log prune", "err", err)
		} else if dropped > 0 {
			log.Info("op log pruned", "rows", dropped)
		}
		time.Sleep(24 * time.Hour)
	}
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
	for {
		if err := db.SweepReports(ctx); err != nil {
			log.Error("report sweep", "err", err)
		}
		time.Sleep(sweepInterval)
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
