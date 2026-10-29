package api

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/MohammadBnei/ukubi-go/errs"
	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/keys"
)

// Where a phone fetches the speech recogniser, and the one other route
// besides /healthz and /auth/callback that answers without a bearer token.
//
// It has to be open, and for the same reason those two are: voice-follow is
// deliberately available to a reader who has never signed in, so a phone
// downloading 160 MB has no token and no reason to have one. Before this
// existed the request fell through to the authenticator and answered
// `a bearer token is required` — a Download button that could only fail.
//
// **The bytes never pass through here.** This mints a short-lived presigned
// GET against the store and answers 302; the client follows it and the
// transfer goes phone-to-store. Proxying 160 MB per reader through a pod
// sized for JSON is how this becomes an outage rather than a feature, and the
// store's own route carries no rate limit while this one does.
//
// The reader's `Range` header travels on their own request to the store, so a
// resumed download is answered 206 by the store and this route never sees it.
//
// Objects are keyed by a digest of their own contents —
// base-ar-quran/<version>/<file> — so a re-export with different weights
// cannot land on a key a half-finished download is resuming against. Two int8
// halves that disagree load without complaint and transcribe nothing, which
// is the same silent failure a dynamo-exported graph gives, and it is not a
// thing to debug twice.
const modelsPath = "GET /models/"

// Long enough for a phone on a slow connection to start the transfer, short
// enough that a URL out of a log is worth nothing later. The reader's client
// holds a path and re-asks, so it never holds a URL that can expire.
const modelURLTTL = 15 * time.Minute

type modelStore struct {
	sign   presigner
	bucket string
	log    *slog.Logger
}

// newModelStore is nil when the deployment has no store (m nil).
func newModelStore(m *Models, log *slog.Logger) *modelStore {
	if m == nil {
		return nil
	}
	return &modelStore{
		bucket: m.Bucket,
		// Garage's region, and it is not a cosmetic string: the signature is
		// computed over it, so the wrong one is a 403 rather than a warning.
		sign: presigner{
			endpoint:  m.Endpoint,
			region:    cmpOr(m.Region, "garage"),
			accessKey: m.AccessKey,
			secret:    m.Secret,
		},
		log: log,
	}
}

func (m *modelStore) serve(w http.ResponseWriter, r *http.Request) {
	key := strings.TrimPrefix(r.URL.Path, "/models/")
	// `..` in a key would reach another prefix of the bucket, and the bucket
	// is shared with nothing today but will not always be.
	if key == "" || strings.Contains(key, "..") {
		http.NotFound(w, r)
		return
	}

	signed, err := m.sign.get(m.bucket, key, time.Now(), modelURLTTL)
	if err != nil {
		m.log.ErrorContext(r.Context(), "presign a model", "key", key, "err", err)
		httpx.Error(w, errs.Internal, keys.ModelsUnreachable, "the recogniser cannot be reached")
		return
	}

	// Never cached: the URL in it expires, and a cached 302 outlives it by
	// however long the cache decides.
	w.Header().Set("Cache-Control", "no-store")
	http.Redirect(w, r, signed, http.StatusFound)
}

// notConfigured answers when the deployment has no store, which is every
// local run and any deployment whose secret has not landed yet.
//
// 503 rather than 404: the reader's phone is fine and the file is not
// missing, and the client turns this into "the recogniser cannot be fetched"
// rather than anything that reads as the reader's own fault.
func modelsNotConfigured(w http.ResponseWriter, _ *http.Request) {
	httpx.Error(w, errs.Unavailable, keys.ModelsNotPublished, "no recogniser is published here")
}

func cmpOr(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
