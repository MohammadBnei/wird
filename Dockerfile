# Two images from one build: `--target api` is wird-api, the binary the phone
# talks to; `--target adminweb` is wird-adminweb, the operations view. ONE
# binary per image still holds. `jidhr/cmd/rootd` is not built here;
# docs/adr/0005-deploying-the-api.md records why, and ADR 0026 records why
# adminweb now is.
#
# The build runs inside server/, the module both binaries belong to. The repo
# root is not a module, and there is no go.work, so `go build ./...` from the
# root does not work. server/go.mod replaces jidhr with ../jidhr (ADR 0035),
# so jidhr's go.mod is copied next to it.
#
# `COPY . .` would be 21 GB — app/ carries Flutter build output. .dockerignore
# covers it, but the copies below are explicit anyway so a stale ignore file
# cannot quietly put the Qur'an corpus into a server image.

# The release this build is (release.yml's --build-arg VERSION). Declared
# before the first FROM so both the build stage and the label can take it;
# "dev" when nobody passes one, as in a local `docker build .`.
ARG VERSION=dev

FROM golang:1.27-alpine AS build

WORKDIR /src/server

# Dependency layer. The replace => ../jidhr does not load without jidhr's
# go.mod on disk. Its go.sum is not needed: Go reads only server/go.sum.
COPY server/go.mod server/go.sum ./
COPY jidhr/go.mod /src/jidhr/
RUN go mod download

# No jidhr source: neither binary imports it, so jidhr edits keep this cache.
COPY server/ ./

# The binaries read their version from an embedded file, not a linker -X var
# (internal/buildinfo says why). After the source COPY, so a new version
# rebuilds only from here. release.yml has already checked its shape.
ARG VERSION
RUN printf '%s\n' "$VERSION" > internal/buildinfo/version.txt

# CGO off: modernc.org/sqlite is pure Go and nothing else here needs a C
# toolchain, so the binary is static and the final stage needs no libc match.
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/wird-api ./cmd/api \
 && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/wird-adminweb ./cmd/adminweb

# Alpine rather than distroless/static. ca-certificates is the load-bearing
# part — go-oidc fetches the issuer's discovery document and JWKS over HTTPS at
# startup, and a certificate-less image dies with an x509 error that reads like
# an authentik outage. Alpine over distroless because it keeps a shell, and the
# first time this pod misbehaves at 3am that is worth more than 6 MB.
FROM alpine:3.22 AS base

RUN apk add --no-cache ca-certificates \
 && adduser -D -u 10001 wird
USER wird
# In base, so both images carry it; the image TAG stays the commit SHA. Last
# here, so a new version does not re-run the apk add above.
ARG VERSION
LABEL org.opencontainers.image.version=$VERSION

FROM base AS adminweb
COPY --from=build /out/wird-adminweb /usr/local/bin/wird-adminweb
# adminweb reads the Nocturne stylesheet from disk at start and refuses to run
# without it. Copied by name, like everything else here, and in this stage
# rather than the build one, so a stylesheet edit does not rebuild both
# binaries. .dockerignore lets this one file through.
COPY docs/design/nocturne-styles.css /usr/share/wird/nocturne-styles.css
ENV NOCTURNE_CSS=/usr/share/wird/nocturne-styles.css
EXPOSE 8081
ENTRYPOINT ["/usr/local/bin/wird-adminweb"]

# Last, so a bare `docker build .` still produces wird-api.
FROM base AS api
COPY --from=build /out/wird-api /usr/local/bin/wird-api
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/wird-api"]
