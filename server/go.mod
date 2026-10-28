module github.com/MohammadBnei/wird/server

go 1.27.1

require (
	github.com/MohammadBnei/ukubi-go v0.0.0-20261028220812-cb6b357f2366
	github.com/MohammadBnei/wird/jidhr v0.0.0
	github.com/coreos/go-oidc/v3 v3.21.0
	github.com/go-jose/go-jose/v4 v4.1.4
	github.com/google/uuid v1.6.0
	github.com/jackc/pgx/v5 v5.11.0
	github.com/pressly/goose/v3 v3.28.0
	github.com/tmc/langchaingo v0.1.14
	golang.org/x/text v0.42.0
	modernc.org/sqlite v1.57.0
)

require (
	github.com/dlclark/regexp2 v1.10.0 // indirect
	github.com/dustin/go-humanize v1.0.1 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/mattn/go-isatty v0.0.24 // indirect
	github.com/mfridman/interpolate v0.0.2 // indirect
	github.com/ncruces/go-strftime v1.0.0 // indirect
	github.com/pkoukk/tiktoken-go v0.1.6 // indirect
	github.com/remyoudompheng/bigfft v0.0.0-20230129092748-24d4a6f8daec // indirect
	github.com/sethvargo/go-retry v0.4.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	golang.org/x/oauth2 v0.36.0 // indirect
	golang.org/x/sync v0.23.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	golang.org/x/tools v0.51.0 // indirect
	modernc.org/libc v1.75.6 // indirect
	modernc.org/mathutil v1.7.1 // indirect
	modernc.org/memory v1.12.1 // indirect
)

// jidhr lives in this repo: server always builds against the jidhr in the same
// commit, so CI tests the two together and there is no pin to bump.
replace github.com/MohammadBnei/wird/jidhr => ../jidhr

tool github.com/MohammadBnei/ukubi-go/cmd/ukubicheck
