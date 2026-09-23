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

	go prune(ctx, db, log)

	addr := env("API_ADDR", ":8080")
	log.Info("wird-api listening", "addr", addr, "issuer", issuer)
	if err := http.ListenAndServe(addr, api.Routes(db, authenticator, log)); err != nil {
		log.Error("wird-api stopped", "err", err)
		os.Exit(1)
	}
}

// ponytail: a ticker in the process, because the op log is the one table that
// grows with every write a reader ever makes and nothing else prunes it. Move
// it to a cron job if the API ever runs as more than one replica.
func prune(ctx context.Context, db *store.Store, log *slog.Logger) {
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

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
