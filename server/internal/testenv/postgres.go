// Package testenv gives a test a real Postgres 18 it can ruin and a real OIDC
// issuer it can mint tokens from. Both are thrown away with the test.
package testenv

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
)

var counter atomic.Int64

// Postgres creates a database of its own, migrates it, and drops it when the
// test ends. Tests share the server from docker-compose and never the schema,
// so one test's rows can never be another's answer.
func Postgres(t *testing.T) (*store.Store, *pgxpool.Pool) {
	t.Helper()
	ctx := t.Context()

	admin := os.Getenv("DATABASE_URL")
	if admin == "" {
		admin = "postgres://wird:wird@localhost:5432/wird"
	}

	conn, err := pgx.Connect(ctx, admin)
	if err != nil {
		t.Fatalf("no Postgres to test against (%v). Run: docker compose up -d postgres", err)
	}
	name := fmt.Sprintf("wird_test_%d_%d", os.Getpid(), counter.Add(1))
	if _, err := conn.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatalf("create test database: %v", err)
	}
	if err := conn.Close(ctx); err != nil {
		t.Fatalf("close admin connection: %v", err)
	}

	dsn := withDatabase(t, admin, name)
	if err := store.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate test database: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect to test database: %v", err)
	}

	t.Cleanup(func() {
		pool.Close()
		// A fresh context: t.Context is already cancelled by now.
		drop, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		conn, err := pgx.Connect(drop, admin)
		if err != nil {
			t.Logf("test database %s left behind: %v", name, err)
			return
		}
		defer conn.Close(drop)
		if _, err := conn.Exec(drop, "DROP DATABASE "+name+" WITH (FORCE)"); err != nil {
			t.Logf("test database %s left behind: %v", name, err)
		}
	})

	return store.New(pool), pool
}

func withDatabase(t *testing.T, dsn, name string) string {
	t.Helper()
	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("DATABASE_URL is not a url: %v", err)
	}
	parsed.Path = "/" + name
	return parsed.String()
}
