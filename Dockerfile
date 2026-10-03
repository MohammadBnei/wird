# Two images from one build: `--target api` is wird-api, the binary the phone
# talks to; `--target adminweb` is wird-adminweb, the operations view. ONE
# binary per image still holds. `jidhr/cmd/rootd` is not built here;
# docs/adr/0005-deploying-the-api.md records why, and ADR 0026 records why
# adminweb now is.
#
# `COPY . . && go build ./...` does not work in this repo and is not a style
# preference: the root is a go.work workspace that is not itself a module, so
# `go build ./...` from here fails with "directory prefix . does not contain
# modules listed in go.work". Both modules are named explicitly, the way
# README.md and scripts/qa.sh already name them.
#
# `COPY . .` is also 21 GB — app/ carries Flutter build output. .dockerignore
# covers it, but the copies below are explicit anyway so a stale ignore file
# cannot quietly put the Qur'an corpus into a server image.
FROM golang:1.27-alpine AS build

WORKDIR /src

# Dependency layer. jidhr has no go.sum because it has no dependencies; the
# workspace still refuses to load without its go.mod on disk.
COPY go.work go.work.sum ./
COPY server/go.mod server/go.sum server/
COPY jidhr/go.mod jidhr/
RUN go mod download

COPY server/ server/
COPY jidhr/ jidhr/

# CGO off: modernc.org/sqlite is pure Go and nothing else here needs a C
# toolchain, so the binary is static and the final stage needs no libc match.
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/wird-api ./server/cmd/api \
 && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/wird-adminweb ./server/cmd/adminweb

# Alpine rather than distroless/static. ca-certificates is the load-bearing
# part — go-oidc fetches the issuer's discovery document and JWKS over HTTPS at
# startup, and a certificate-less image dies with an x509 error that reads like
# an authentik outage. Alpine over distroless because it keeps a shell, and the
# first time this pod misbehaves at 3am that is worth more than 6 MB.
FROM alpine:3.22 AS base

RUN apk add --no-cache ca-certificates \
 && adduser -D -u 10001 wird
USER wird

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
