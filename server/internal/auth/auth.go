// Package auth turns a bearer token into the reader it belongs to. We mint no
// tokens: the only thing that happens here is validating someone else's
// against the issuer's JWKS.
package auth

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"

	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

type Authenticator struct {
	verifier *oidc.IDTokenVerifier
	users    *store.Store
	log      *slog.Logger
}

// New discovers the issuer named by OIDC_ISSUER and builds a verifier for it.
// Swapping the local stub for authentik.bnei.dev is that one variable; no code
// on this path knows which of the two it is talking to.
func New(ctx context.Context, issuer, audience string, users *store.Store, log *slog.Logger) (*Authenticator, error) {
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, err
	}
	return &Authenticator{
		verifier: provider.Verifier(&oidc.Config{ClientID: audience}),
		users:    users,
		log:      log,
	}, nil
}

type ctxKey struct{}

// Middleware refuses anything it cannot verify, and only then looks up — or
// mints — the reader. A subject read out of an unverified token is an account
// handed to whoever wrote the token.
func (a *Authenticator) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := bearer(r)
		if !ok {
			httpx.Error(w, http.StatusUnauthorized, "a bearer token is required")
			return
		}
		token, err := a.verifier.Verify(r.Context(), raw)
		if err != nil {
			a.log.Info("token refused", "err", err)
			httpx.Error(w, http.StatusUnauthorized, "token rejected")
			return
		}
		if token.Subject == "" {
			httpx.Error(w, http.StatusUnauthorized, "token rejected")
			return
		}
		if refused, err := a.signedInBeforeDeletion(r.Context(), token); err != nil {
			a.log.Error("deletion lookup", "err", err)
			httpx.Error(w, http.StatusInternalServerError, "unavailable")
			return
		} else if refused {
			httpx.Error(w, http.StatusUnauthorized, "token rejected")
			return
		}
		user, err := a.users.EnsureUser(r.Context(), token.Subject)
		if err != nil {
			a.log.Error("reader lookup", "err", err)
			httpx.Error(w, http.StatusInternalServerError, "unavailable")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, user)))
	})
}

// signedInBeforeDeletion is true for a token whose sign-in predates its
// subject's account deletion, which would otherwise mint the account straight
// back. auth_time, not iat: a refresh mints a new iat and keeps auth_time, so
// iat would let any phone still holding a refresh token through. A deleted
// subject's token without auth_time is refused, since nothing proves it came
// after. The deletion moment is cut to the second because auth_time is.
func (a *Authenticator) signedInBeforeDeletion(ctx context.Context, token *oidc.IDToken) (bool, error) {
	deletedAt, deleted, err := a.users.ReaderDeletedAt(ctx, token.Subject)
	if err != nil || !deleted {
		return false, err
	}
	var claims struct {
		AuthTime int64 `json:"auth_time"`
	}
	if err := token.Claims(&claims); err != nil || claims.AuthTime == 0 {
		return true, nil
	}
	return time.Unix(claims.AuthTime, 0).Before(deletedAt.Truncate(time.Second)), nil
}

func bearer(r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	scheme, token, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "bearer") || token == "" {
		return "", false
	}
	return token, true
}

// User is the reader this request is for. It is only ever absent when the
// handler was reached without the middleware, which is a wiring bug.
func User(ctx context.Context) store.User {
	user, _ := ctx.Value(ctxKey{}).(store.User)
	return user
}
