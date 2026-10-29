package main

import (
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/MohammadBnei/ukubi-go/telemetry"
)

func main() {
	// Logs on stderr: stdout is the report.
	slog.SetDefault(telemetry.NewLogger(os.Stderr))
	cfg, err := fromProcess() // ExitOnError: a bad flag exits 2
	if err != nil {
		slog.Error("config refused", "err", err)
		os.Exit(1)
	}

	c, err := Load(cfg.In, Recitations)
	if err != nil {
		slog.Error("read", "path", cfg.In, "err", err)
		os.Exit(1)
	}
	if err := c.Check(cfg.Full); err != nil {
		slog.Error("corpus rejected", "err", err)
		os.Exit(1)
	}
	if err := Write(cfg.Out, c, cfg.CorpusVersion, time.Now()); err != nil {
		slog.Error("write", "path", cfg.Out, "err", err)
		os.Exit(1)
	}

	fi, err := os.Stat(cfg.Out)
	if err != nil {
		slog.Error("read back the output", "path", cfg.Out, "err", err)
		os.Exit(1)
	}
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d  audio %d\n  parsed segments %d  roles %d\n  words with no French gloss %d\n  %.2f MB\n",
		cfg.Out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots), len(c.Audio),
		len(c.Irab), len(IrabRoles()), c.FrenchGlossesMissed, float64(fi.Size())/(1<<20))
	for _, r := range c.Recited {
		fmt.Printf("  %s: segments %d (clamped %d)  words with no timing %d\n",
			r.Slug, len(r.Segments), r.Clamped, r.Untimed)
	}
	for _, r := range c.Refused {
		fmt.Printf("  REFUSED %s\n", r)
	}
}
