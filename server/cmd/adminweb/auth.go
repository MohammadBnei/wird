package main

import (
	"context"
	"log/slog"
	"net/http"
	"slices"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/go-jose/go-jose/v4"
)

// clientSecret is the one key a token from authentik's proxy provider can be
// checked with: the provider signs HS256 with its client secret. Only HS256 is
// parsed, so a token whose header names another algorithm is refused before
// any key is tried.
type clientSecret []byte

func (k clientSecret) VerifySignature(_ context.Context, raw string) ([]byte, error) {
	jws, err := jose.ParseSigned(raw, []jose.SignatureAlgorithm{jose.HS256})
	if err != nil {
		return nil, err
	}
	return jws.Verify([]byte(k))
}

// clientSecretVerifier checks issuer, audience and expiry exactly as the
// discovery path does; only the key differs. Each provider has its own secret,
// so a token another provider minted does not even verify here.
func clientSecretVerifier(issuer, audience, secret string) *oidc.IDTokenVerifier {
	return oidc.NewVerifier(issuer, clientSecret(secret), &oidc.Config{
		ClientID:             audience,
		SupportedSigningAlgs: []string{string(jose.HS256)},
	})
}

// The group Authentik already keeps. Grafana reads this same membership list
// for Admin and ArgoCD for role:admin; Wird's operations view is the third
// reader of it, and holds no list of its own. There is deliberately no lookup
// of a Wird user on this path: the users table is readers, and an operator is
// somebody Authentik says is in the group.
const operatorGroup = "platform-admins"

func operators(verifier *oidc.IDTokenVerifier, log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := presentedToken(r)
		if !ok {
			http.Error(w, "sign in through the proxy", http.StatusUnauthorized)
			return
		}
		token, err := verifier.Verify(r.Context(), raw)
		if err != nil {
			log.Info("token refused", "err", err)
			http.Error(w, "token rejected", http.StatusUnauthorized)
			return
		}
		var claims struct {
			Groups []string `json:"groups"`
		}
		if err := token.Claims(&claims); err != nil || !slices.Contains(claims.Groups, operatorGroup) {
			log.Info("not an operator", "group", operatorGroup)
			http.Error(w, "this page is for "+operatorGroup, http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Any of these headers carries the token, and none is trusted as an assertion:
// the signature and the audience are checked whichever one it arrives in, so a
// header set by anything that can reach this port buys nothing.
// X-authentik-jwt is the one authentik's outpost actually forwards; its
// X-authentik-groups beside it is exactly the unsigned claim this never reads.
// The group check below is load-bearing even for a well-signed token: the
// proxy provider always allows the password grant, so any directory user can
// mint a token for this audience.
func presentedToken(r *http.Request) (string, bool) {
	for _, h := range []string{"X-authentik-jwt", "X-Forwarded-Access-Token"} {
		if raw := r.Header.Get(h); raw != "" {
			return raw, true
		}
	}
	scheme, raw, found := strings.Cut(r.Header.Get("Authorization"), " ")
	if !found || !strings.EqualFold(scheme, "bearer") || raw == "" {
		return "", false
	}
	return raw, true
}
