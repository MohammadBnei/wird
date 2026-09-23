package main

import (
	"archive/zip"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/timings"
)

// The word timings, and the only file in this ingest that may be bundled in an
// immutable asset on terms that say so. The release package is the unit that
// carries the grant: the LICENCE and the README travel inside it, and the
// repository's own top-level LICENSE is MIT and covers the aligner, not the data.
const (
	alignURL   = "https://github.com/cpfair/quran-align/releases/download/release-2016-11-24/quran-align-data-2016-11-24.zip"
	alignZip   = "quran-align-data-2016-11-24.zip"
	timingsDir = "timings"
)

// extractTimings pulls one recitation out of the release package, together with
// the licence and the README the grant is written in.
//
// It refuses a package whose README no longer carries the licence sentence
// corpus_meta.notice quotes. A quote that has stopped being a quote is the
// morphology fork's mistake in a second place: data shipped under a permission
// nobody re-read.
func extractTimings(zipPath, dir, recitation string) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("%s: %w", zipPath, err)
	}
	defer zr.Close()

	want := map[string]bool{recitation + ".json": true, "LICENSE": true, "README": true}
	for _, f := range zr.File {
		name := filepath.Base(f.Name)
		if !want[name] {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		b, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			return err
		}
		if name == "README" && !strings.Contains(string(b), timings.LicenceMarker) {
			return fmt.Errorf("%s no longer says %q in its README. That sentence is the whole of "+
				"the permission to bundle these timings, and corpus_meta.notice quotes it; read the "+
				"package's own terms again before shipping it", alignURL, timings.LicenceMarker)
		}
		if err := save(filepath.Join(dir, timingsDir, name), b); err != nil {
			return err
		}
		delete(want, name)
	}
	if len(want) > 0 {
		missing := make([]string, 0, len(want))
		for name := range want {
			missing = append(missing, name)
		}
		return fmt.Errorf("%s holds no %s; %s covers 12 recitations and ships its licence beside them",
			zipPath, strings.Join(missing, ", "), alignURL)
	}
	return nil
}
