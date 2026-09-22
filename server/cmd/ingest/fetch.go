package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

const userAgent = "wird-ingest/1 (+https://github.com/MohammadBnei/wird)"

// fetcher makes one request at a time, spaced by delay, and backs off when the
// host says to. The sources are free and unauthenticated; hammering them is how
// a project loses access to them.
type fetcher struct {
	hc      *http.Client
	delay   time.Duration
	retries int

	base     time.Duration // first backoff step; a second unless a test shortens it
	next     time.Time
	requests int // fetches actually sent, so a resumed run can prove it skipped
}

func (f *fetcher) get(ctx context.Context, url string) ([]byte, error) {
	var lastErr error
	for attempt := 0; attempt <= f.retries; attempt++ {
		if d := time.Until(f.next); d > 0 {
			time.Sleep(d)
		}
		f.next = time.Now().Add(f.delay)
		f.requests++

		body, wait, err := f.try(ctx, url)
		if err == nil {
			return body, nil
		}
		lastErr = err
		if wait < 0 || ctx.Err() != nil {
			return nil, err
		}
		if wait == 0 {
			wait = f.backoff(attempt)
		}
		time.Sleep(wait)
	}
	return nil, fmt.Errorf("gave up after %d attempts: %w", f.retries+1, lastErr)
}

// try returns a negative wait for an error worth giving up on immediately.
func (f *fetcher) try(ctx context.Context, url string) (body []byte, wait time.Duration, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, -1, err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := f.hc.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode == http.StatusTooManyRequests:
		return nil, retryAfter(resp.Header.Get("Retry-After")), fmt.Errorf("GET %s: %s", url, resp.Status)
	case resp.StatusCode >= 500:
		return nil, 0, fmt.Errorf("GET %s: %s", url, resp.Status)
	case resp.StatusCode != http.StatusOK:
		return nil, -1, fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, fmt.Errorf("GET %s: %w", url, err)
	}
	return b, 0, nil
}

func (f *fetcher) backoff(attempt int) time.Duration {
	base := f.base
	if base <= 0 {
		base = time.Second
	}
	d := base << attempt
	if d > time.Minute {
		d = time.Minute
	}
	return d
}

func retryAfter(h string) time.Duration {
	if n, err := strconv.Atoi(h); err == nil && n >= 0 {
		if d := time.Duration(n) * time.Second; d <= 5*time.Minute {
			return d
		}
	}
	return 0
}

// download fetches url into path unless path already holds a finished download.
// Writing through a temp file is what makes that test safe: a run killed mid
// -write leaves no half file for the next run to mistake for a complete one.
func (f *fetcher) download(ctx context.Context, url, path string, force bool) error {
	if !force {
		if fi, err := os.Stat(path); err == nil && fi.Size() > 0 {
			return nil
		}
	}
	b, err := f.get(ctx, url)
	if err != nil {
		return err
	}
	return save(path, b)
}

func save(path string, b []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".part"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
