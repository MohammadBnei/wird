package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
)

// The seed corpus is shared with the resolver's own tests, so rootd is exercised
// against the words the ladder is specified against rather than a second fixture
// that can drift from it.
const corpusPath = "../../testdata/corpus.json"

const (
	attestedWord     = "وَتَوَاصَوْا" // an exact Qur'anic spelling
	borrowedName     = "إسطنبول"      // good Arabic, no derivable root
	nonQuranicWord   = "بَرمَجَة"     // Arabic with a root the Qur'an never uses
	attestedLetters  = "وصي"
	shapeOnlyWord    = "مالك" // good Arabic whose root only a template proposes, so it is never served one
	untransliterated = "ملك"  // a root the seed corpus records without a transliteration
)

func testServer(t *testing.T, store root.Store) *server {
	t.Helper()
	if store == nil {
		f, err := os.Open(filepath.Clean(corpusPath))
		if err != nil {
			t.Fatalf("open the seed corpus: %v", err)
		}
		defer f.Close()
		memory, err := root.LoadMemoryStore(f)
		if err != nil {
			t.Fatalf("load the seed corpus: %v", err)
		}
		store = memory
	}
	return &server{
		resolver: root.New(store),
		store:    store,
		log:      slog.New(slog.DiscardHandler),
	}
}

func call(t *testing.T, s *server, r *http.Request) (int, map[string]any) {
	t.Helper()
	w := httptest.NewRecorder()
	s.routes().ServeHTTP(w, r)

	body := map[string]any{}
	if w.Body.Len() > 0 {
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatalf("the response is not JSON: %v\n%s", err, w.Body.String())
		}
	}
	return w.Code, body
}

func get(t *testing.T, s *server, target string) (int, map[string]any) {
	t.Helper()
	return call(t, s, httptest.NewRequest(http.MethodGet, target, nil))
}

func postBatch(t *testing.T, s *server, words []string) (int, map[string]any) {
	t.Helper()
	body, err := json.Marshal(batchRequest{Words: words})
	if err != nil {
		t.Fatalf("marshal the batch: %v", err)
	}
	return call(t, s, httptest.NewRequest(http.MethodPost, "/v1/roots:batch", strings.NewReader(string(body))))
}

func wordURL(word string) string {
	return "/v1/root?word=" + url.QueryEscape(word) + "&lang=en,ar"
}

func errorCode(t *testing.T, body map[string]any) string {
	t.Helper()
	fail, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("the response carries no error object: %v", body)
	}
	code, _ := fail["code"].(string)
	return code
}

func TestANonArabicWordIsRefusedAsBadInputRatherThanReportedAsAMissingRoot(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, wordURL("hello"))

	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d: a caller sending Latin text is told the word has no root, so it never learns to fix its input", status, http.StatusBadRequest)
	}
	if code := errorCode(t, body); code != "not_arabic" {
		t.Errorf("code = %q, want %q", code, "not_arabic")
	}
}

func TestAnArabicWordWithNoDerivableRootIsNotFoundWithTheCandidatesItConsidered(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, wordURL(borrowedName))

	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want %d: perfectly good Arabic is reported as bad input", status, http.StatusNotFound)
	}
	if code := errorCode(t, body); code != "no_root" {
		t.Errorf("code = %q, want %q", code, "no_root")
	}
	fail := body["error"].(map[string]any)
	if candidates, _ := fail["candidates"].([]any); len(candidates) == 0 {
		t.Error("the 404 names nothing it tried, so the caller cannot tell a missing entry from a broken stripper")
	}
}

func TestAMissingWordParameterIsBadInputRatherThanASilentEmptyAnswer(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, "/v1/root?lang=en")

	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", status, http.StatusBadRequest)
	}
	if code := errorCode(t, body); code != "missing_word" {
		t.Errorf("code = %q, want %q: a caller whose word parameter never arrived is told its word is not Arabic", code, "missing_word")
	}
}

func TestTheRootResponseNeverShipsAConfidenceScore(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, wordURL(attestedWord))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: %v", status, http.StatusOK, body)
	}
	if carries(body, "confidence") {
		t.Error("the response carries a confidence score, so callers branch on a float nobody defined instead of on the rung that answered")
	}
	if body["method"] != string(root.MethodLexicon) {
		t.Errorf("method = %v, want %q: the rung that answered is the only confidence there is", body["method"], root.MethodLexicon)
	}
}

func TestAWordOutsideTheQuranComesBackWithoutAQuranStatistic(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, wordURL(nonQuranicWord))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: %v", status, http.StatusOK, body)
	}
	if _, present := body["quran"]; present {
		t.Error("an ordinary Arabic word is answered with a Qur'an statistic the caller never asked for")
	}
}

func TestARootIsAddressedByItsJoinedLettersAndNotItsSpacedDisplay(t *testing.T) {
	s := testServer(t, nil)

	status, body := get(t, s, "/v1/roots/"+url.PathEscape(attestedLetters)+"?lang=en")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: %v", status, http.StatusOK, body)
	}
	got, _ := body["root"].(map[string]any)
	if got["letters"] != attestedLetters {
		t.Errorf("letters = %v, want %q", got["letters"], attestedLetters)
	}
	if got["display"] != "و ص ي" {
		t.Errorf("display = %v, want the spaced presentation", got["display"])
	}

	spaced, _ := get(t, s, "/v1/roots/"+url.PathEscape("و ص ي"))
	if spaced == http.StatusOK {
		t.Error("the spaced display also addresses the root, so two callers percent-encode two different keys for one root")
	}
}

func TestARootOutsideTheQuranIsServedWithoutAQuranObject(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, "/v1/roots/"+url.PathEscape("برمج"))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: %v", status, http.StatusOK, body)
	}
	if _, present := body["quran"]; present {
		t.Error("a root the Qur'an never uses is served with an occurrence count, which a caller will read as zero occurrences rather than as no data")
	}
}

func TestAnUnrecordedRootIsNotFoundRatherThanAnEmptyRoot(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, "/v1/roots/"+url.PathEscape("زبر"))

	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want %d: an unknown root answers 200 with blank fields, which renders as a root with no meaning", status, http.StatusNotFound)
	}
	if code := errorCode(t, body); code != "no_root" {
		t.Errorf("code = %q, want %q", code, "no_root")
	}
}

func TestLatinLettersInARootPathAreBadInputRatherThanAnUnknownRoot(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, "/v1/roots/ktb")

	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d: a caller sending a transliteration is told the root does not exist, so it keeps sending transliterations", status, http.StatusBadRequest)
	}
	if code := errorCode(t, body); code != "not_arabic" {
		t.Errorf("code = %q, want %q", code, "not_arabic")
	}
}

func TestABatchOverTheCapIsRefusedRatherThanQuietlyTruncated(t *testing.T) {
	s := testServer(t, nil)
	words := make([]string, maxBatchWords+1)
	for i := range words {
		words[i] = attestedWord
	}

	status, body := postBatch(t, s, words)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d: one request buys unbounded work on a public endpoint", status, http.StatusBadRequest)
	}
	if code := errorCode(t, body); code != "batch_too_large" {
		t.Errorf("code = %q, want %q", code, "batch_too_large")
	}
	if _, answered := body["results"]; answered {
		t.Error("an over-sized batch still came back with results, so the caller cannot tell which of its words were dropped")
	}
}

func TestABatchAtTheCapIsAnswered(t *testing.T) {
	s := testServer(t, nil)
	words := make([]string, maxBatchWords)
	for i := range words {
		words[i] = attestedWord
	}

	status, body := postBatch(t, s, words)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: the documented maximum is refused, so the cap is really %d", status, http.StatusOK, maxBatchWords-1)
	}
	if got := len(body["results"].([]any)); got != maxBatchWords {
		t.Errorf("results = %d, want %d", got, maxBatchWords)
	}
}

func TestOneUnresolvableWordDoesNotSinkTheRestOfTheBatch(t *testing.T) {
	s := testServer(t, nil)
	status, body := postBatch(t, s, []string{attestedWord, "hello", borrowedName})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: a page of words is refused wholesale because one of them is a name", status, http.StatusOK)
	}

	results, _ := body["results"].([]any)
	if len(results) != 3 {
		t.Fatalf("results = %d, want 3", len(results))
	}
	answered, _ := results[0].(map[string]any)
	if _, ok := answered["result"]; !ok {
		t.Error("the resolvable word lost its answer because other words in the batch failed")
	}
	for i, wantStatus := range map[int]float64{1: http.StatusBadRequest, 2: http.StatusNotFound} {
		item, _ := results[i].(map[string]any)
		fail, ok := item["error"].(map[string]any)
		if !ok {
			t.Fatalf("word %d came back without an error: %v", i, item)
		}
		if fail["status"] != wantStatus {
			t.Errorf("word %d status = %v, want %v: the batch collapses bad input and an unknown word into one answer", i, fail["status"], wantStatus)
		}
	}
}

func TestACorpusOutageIsAServerFailureAndNotAWordWithNoRoot(t *testing.T) {
	s := testServer(t, failingStore{err: errors.New("the corpus is unreachable")})
	status, body := get(t, s, wordURL(attestedWord))

	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d: an outage reads to every caller as a word with no root", status, http.StatusInternalServerError)
	}
	if code := errorCode(t, body); code != "internal" {
		t.Errorf("code = %q, want %q", code, "internal")
	}
	if strings.Contains(strings.ToLower(fmt.Sprint(body)), "unreachable") {
		t.Error("the corpus failure is quoted to the caller, so an internal detail leaves the building")
	}
}

func TestACorpusOutageFailsTheWholeBatchInsteadOfAnsweringSomeWords(t *testing.T) {
	s := testServer(t, failingStore{err: errors.New("the corpus is unreachable")})
	status, body := postBatch(t, s, []string{attestedWord, attestedWord})

	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d: a batch run against a dead corpus answers 200, so partial results look complete", status, http.StatusInternalServerError)
	}
	if _, answered := body["results"]; answered {
		t.Error("the failed batch still carries results")
	}
}

func TestAFloodFromOneCallerIsThrottledInsteadOfServed(t *testing.T) {
	s := testServer(t, nil)
	s.limiter = newLimiter(0.001, 2)

	for attempt := 1; attempt <= 2; attempt++ {
		if status, _ := get(t, s, wordURL(attestedWord)); status != http.StatusOK {
			t.Fatalf("request %d: status = %d, want %d — the allowed burst is being refused", attempt, status, http.StatusOK)
		}
	}
	status, body := get(t, s, wordURL(attestedWord))
	if status != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d: one caller can spend the whole public engine", status, http.StatusTooManyRequests)
	}
	if code := errorCode(t, body); code != "rate_limited" {
		t.Errorf("code = %q, want %q", code, "rate_limited")
	}
}

func TestOneNoisyCallerDoesNotSpendAnotherCallersBudget(t *testing.T) {
	l := newLimiter(0.001, 1)
	now := time.Now()

	if !l.allow("192.0.2.1", now) || l.allow("192.0.2.1", now) {
		t.Fatal("the noisy caller was not throttled, so this proves nothing about the quiet one")
	}
	if !l.allow("198.51.100.7", now) {
		t.Error("a second caller is refused because the first one flooded, so one client takes the service down for everybody")
	}
}

func TestAThrottledCallerIsServedAgainOnceItsBucketRefills(t *testing.T) {
	l := newLimiter(1, 1)
	now := time.Now()

	if !l.allow("192.0.2.1", now) || l.allow("192.0.2.1", now) {
		t.Fatal("the caller was not throttled, so this proves nothing about the refill")
	}
	if !l.allow("192.0.2.1", now.Add(2*time.Second)) {
		t.Error("the bucket never refills, so a caller that trips the limit once is locked out for good")
	}
}

func TestAnAnonymousCallIsRefusedWhenAnApiKeyIsConfigured(t *testing.T) {
	s := testServer(t, nil)
	s.apiKey = "a-secret-nobody-guesses"

	status, body := get(t, s, wordURL(attestedWord))
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d: the key is configured and ignored, so the deployment believes it is closed while it is open", status, http.StatusUnauthorized)
	}
	if code := errorCode(t, body); code != "unauthorized" {
		t.Errorf("code = %q, want %q", code, "unauthorized")
	}

	r := httptest.NewRequest(http.MethodGet, wordURL(attestedWord), nil)
	r.Header.Set("Authorization", "Bearer "+s.apiKey)
	if status, body := call(t, s, r); status != http.StatusOK {
		t.Errorf("the configured key was itself refused: status = %d, %v", status, body)
	}
}

func TestHealthChecksSurviveTheApiKeyAndTheRateLimit(t *testing.T) {
	s := testServer(t, nil)
	s.apiKey = "a-secret-nobody-guesses"
	s.limiter = newLimiter(0, 0)

	w := httptest.NewRecorder()
	s.routes().ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d: the orchestrator's probe is throttled or rejected, so a healthy process is restarted in a loop", w.Code, http.StatusOK)
	}
}

func TestARootTheCorpusHasNoTransliterationForOmitsTheFieldRatherThanShippingItBlank(t *testing.T) {
	s := testServer(t, nil)
	status, body := get(t, s, "/v1/roots/"+url.PathEscape(untransliterated))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d: %v", status, http.StatusOK, body)
	}

	got, _ := body["root"].(map[string]any)
	if got["letters"] != untransliterated {
		t.Fatalf("letters = %v, want %q", got["letters"], untransliterated)
	}
	if _, present := got["translit"]; present {
		t.Error("a root nobody has transliterated yet ships an empty translit, which the reader is shown as its transliteration")
	}
}

func TestAMissTellsTheCallerWhichReadingsTheCorpusKnowsAndWhichOnlyFitAShape(t *testing.T) {
	// For a word only the templates have anything to say about, the 404 is the whole
	// answer, so it carries the readings ranked and marked. A bare list of letters
	// reads as a verdict and its first line reads as the root, which is exactly the
	// claim this engine cannot make.
	s := testServer(t, nil)
	status, body := get(t, s, wordURL(shapeOnlyWord))
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want %d: a reading that merely fits a shape was served as this word's root: %v", status, http.StatusNotFound, body)
	}

	fail, _ := body["error"].(map[string]any)
	candidates, _ := fail["candidates"].([]any)
	if len(candidates) == 0 {
		t.Fatalf("the 404 names nothing it considered: %v", body)
	}

	known, shaped := 0, 0
	for i, entry := range candidates {
		c, isObject := entry.(map[string]any)
		if !isObject {
			t.Fatalf("candidate %d is %v, so the caller cannot tell an attested reading from a shape that fits", i, entry)
		}
		if c["letters"] == nil {
			t.Errorf("candidate %d carries no letters: %v", i, c)
		}
		if c["known"] == true {
			known++
			if shaped > 0 {
				t.Errorf("%v is attested and sits below %d readings that are not, so the ranking is not the order the caller reads", c["letters"], shaped)
			}
			continue
		}
		shaped++
	}
	if known == 0 || shaped == 0 {
		t.Errorf("the 404 reports %d attested and %d unattested readings, so the mark that tells them apart cannot be read: %v", known, shaped, candidates)
	}
}

func TestTheRootPathAndTheWordPathAgreeOnWhatCountsAsArabic(t *testing.T) {
	s := testServer(t, nil)

	for _, input := range []string{"hello", "١٢٣", "ًٌٍ", attestedLetters, shapeOnlyWord} {
		wordStatus, wordBody := get(t, s, wordURL(input))
		rootStatus, rootBody := get(t, s, "/v1/roots/"+url.PathEscape(input))

		byWord := refusedAsNotArabic(wordStatus, wordBody)
		byRoot := refusedAsNotArabic(rootStatus, rootBody)
		if byWord != byRoot {
			t.Errorf("%q: /v1/root refuses it as non-Arabic: %v; /v1/roots/{letters}: %v — one half of jidhr refuses input the other half answers",
				input, byWord, byRoot)
		}
	}
}

func refusedAsNotArabic(status int, body map[string]any) bool {
	if status != http.StatusBadRequest {
		return false
	}
	fail, _ := body["error"].(map[string]any)
	return fail["code"] == "not_arabic"
}

// carries reports whether key appears anywhere in a decoded JSON document.
func carries(v any, key string) bool {
	switch value := v.(type) {
	case map[string]any:
		for k, nested := range value {
			if k == key || carries(nested, key) {
				return true
			}
		}
	case []any:
		for _, nested := range value {
			if carries(nested, key) {
				return true
			}
		}
	}
	return false
}

// failingStore stands in for a corpus that is down rather than one that is empty.
type failingStore struct{ err error }

func (s failingStore) EntryBySurface(context.Context, string) (root.Entry, error) {
	return root.Entry{}, s.err
}

func (s failingStore) EntryByNormalized(context.Context, string) (root.Entry, error) {
	return root.Entry{}, s.err
}

func (s failingStore) EntryByLemma(context.Context, string) (root.Entry, error) {
	return root.Entry{}, s.err
}

func (s failingStore) Attests(context.Context, string) ([]string, error) {
	return nil, s.err
}

func (s failingStore) Root(context.Context, string) (root.RootRecord, error) {
	return root.RootRecord{}, s.err
}

func (s failingStore) Meanings(context.Context, string, []string) (map[string]root.Meaning, error) {
	return nil, s.err
}
