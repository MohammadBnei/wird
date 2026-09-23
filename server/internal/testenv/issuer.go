package testenv

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// Issuer is a real OIDC issuer: discovery, a JWKS, and RS256 tokens signed by
// the key it publishes. The verifier under test fetches and checks all of it
// over HTTP, so a test can hold a token that is genuinely expired, or
// genuinely signed by somebody else.
type Issuer struct {
	URL string
	key *rsa.PrivateKey
}

func NewIssuer(t *testing.T) *Issuer {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("issuer key: %v", err)
	}
	iss := &Issuer{key: key}

	mux := http.NewServeMux()
	server := httptest.NewUnstartedServer(mux)
	iss.URL = "http://" + server.Listener.Addr().String()

	mux.HandleFunc("GET /.well-known/openid-configuration", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{
			"issuer":                                iss.URL,
			"jwks_uri":                              iss.URL + "/jwks",
			"authorization_endpoint":                iss.URL + "/auth",
			"token_endpoint":                        iss.URL + "/token",
			"response_types_supported":              []string{"code"},
			"subject_types_supported":               []string{"public"},
			"id_token_signing_alg_values_supported": []string{"RS256"},
		})
	})
	mux.HandleFunc("GET /jwks", func(w http.ResponseWriter, _ *http.Request) {
		e := make([]byte, 4)
		binary.BigEndian.PutUint32(e, uint32(key.E))
		writeJSON(w, map[string]any{"keys": []map[string]string{{
			"kty": "RSA",
			"kid": "testenv",
			"alg": "RS256",
			"use": "sig",
			"n":   raw(key.N.Bytes()),
			"e":   raw(strings.TrimLeft(string(e), "\x00")),
		}}})
	})

	server.Start()
	t.Cleanup(server.Close)
	return iss
}

// Token signs a token for subject, good for lifetime. A negative lifetime
// produces one that expired that long ago.
func (i *Issuer) Token(t *testing.T, subject, audience string, lifetime time.Duration) string {
	t.Helper()
	now := time.Now()
	header := raw(marshal(t, map[string]string{"alg": "RS256", "typ": "JWT", "kid": "testenv"}))
	claims := raw(marshal(t, map[string]any{
		"iss": i.URL,
		"sub": subject,
		"aud": audience,
		"iat": now.Unix(),
		"exp": now.Add(lifetime).Unix(),
	}))
	signing := header + "." + claims
	digest := sha256.Sum256([]byte(signing))
	signature, err := rsa.SignPKCS1v15(rand.Reader, i.key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return signing + "." + raw(signature)
}

func raw[T ~string | ~[]byte](b T) string {
	return base64.RawURLEncoding.EncodeToString([]byte(b))
}

func marshal(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return b
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
