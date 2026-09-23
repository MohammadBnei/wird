package main

import (
	"log/slog"
	"net/http"
	"slices"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
)

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

// Either header carries the token the proxy forwarded, and neither is trusted
// as an assertion: the signature and the audience are checked whichever one it
// arrives in, so a header set by anything that can reach this port buys
// nothing.
func presentedToken(r *http.Request) (string, bool) {
	if raw := r.Header.Get("X-Forwarded-Access-Token"); raw != "" {
		return raw, true
	}
	scheme, raw, found := strings.Cut(r.Header.Get("Authorization"), " ")
	if !found || !strings.EqualFold(scheme, "bearer") || raw == "" {
		return "", false
	}
	return raw, true
}
