// Package migrations carries the goose migrations as bytes, so the test
// database and the running server come up through the same path the
// `goose -dir server/migrations` command takes.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
