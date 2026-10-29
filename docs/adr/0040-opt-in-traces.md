# 40. The servers trace each route when an endpoint is set, and nothing otherwise

Date: 2026-10-29. Status: accepted. Amends ADR 0039 (rootd's logger, and its reason that the jidhr module keeps no dependencies).

## Context

The ukubi Code Standard §7 asks for traces through ukubi-go's `telemetry` package: one server span per route, named by its pattern, pushed over OTLP/HTTP, and inert when no endpoint is configured. The span is placed outside any gate, so a refused request is traced too. A caller's `traceparent` starts a new linked trace rather than a child, because any caller can send one. The trace backend is still open, and nothing deploys a collector yet.

wird has three servers: wird-api, wird-adminweb and rootd. api and adminweb already used ukubi-go for their logger only. rootd used a stdlib JSON handler, so that the jidhr module could keep no dependencies (ADR 0039).

api and rootd had one gate each: the outer mux handed every path it did not know to the auth middleware (rootd: the limiter, then the key) wrapped around an inner mux. The outer mux never saw a gated route's pattern, so it could not name a span by it.

ukubi-go's tracing records `client.address`, `network.peer.address`, `user_agent.original` and `url.path` on every span. For wird-api that is a reader's IP address, user agent and paths such as `/v1/ayahs/2/255/tafsir`, including signed-out phones. The public privacy page says a signed-out reader's phone sends nothing about them anywhere, and lists what the server keeps; traces are not on it. ADR 0004 treats per-reader observability as surveillance unless it is built not to be.

## Decision

- Each server reads one new variable, `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, the traces URL in full. Unset means `telemetry.New` returns a tracing that wraps nothing, so every response is byte for byte what it was. A value that is not an http(s) URL with a host is refused at start with the other configuration problems, by name and never by value. The SDK's catch-all `OTEL_EXPORTER_OTLP_ENDPOINT` is never read.
- Every route but `/healthz` is wrapped in `t.Handler(pattern, h)`, outermost, so the span is outside the gate. `/healthz` and a path no route takes have no span.
- api and rootd keep one gate value. Each gated route is registered from one table: on the inner mux, where its handler lives, and on the outer mux as that same gate under its span. Anything else falls through `"/"` to the same gate, untraced, and the inner mux answers its 404 or 405 after it, as before. A test walks the table with no credentials and wants a refusal under one span per route.
- Tracing is built right after the configuration, before the database, and shut down last. In api and adminweb that is a deferred `Shutdown` registered before `db.Close`, so it runs after the drain and after the database closes. rootd calls it explicitly once `serve` returns, before either exit, since `os.Exit` runs no deferred call. A child-process test per binary proves the span of a request served during the drain reaches a collector before exit.
- rootd's logger becomes `telemetry.NewLogger`, and the jidhr module requires ukubi-go at the same version server pins.
- The command-line tools stay untraced. §7 defines server spans, one per route, and defers propagation on outbound calls, so a CLI has nothing to wrap.
- The endpoint is not to be set for wird-api in production until the privacy page says what traces keep and for how long, or until the address and user-agent attributes are scrubbed. Turning it on is a later owner step.

## Alternatives

- **The span inside the gate** — the outer mux could keep its single `"/"` registration, but then a 401 or a 429 has no span, and the standard asks for refusals to be traced.
- **A bare handler per gated route on the outer mux, each with its own gate** — ten gates in api instead of one, and one handler registered without its gate is a reader's state open to anyone, which no structure would catch.
- **Leave rootd untraced** — nothing deploys it, so it would cost nothing today. But the owner's decision is the standard for every binary, and the cost is one dependency in a module nothing else imports.

## Consequences

- With the variable unset, nothing changes on the wire. The response golden over every route, method and credential gave identical output before and after.
- With it set: one span per route, `trace_id` and `span_id` on log lines written with a request's context, a WARN `traces` line for a failed export, and an ERROR `tracing unavailable` (exit 1) if the exporter cannot be built at start. Spans carry the caller's IP address, user agent and path.
- With it set, otelhttp's response-writer wrapper hides net/http's request-too-large signal, so an over-limit body on `POST /v1/sync`, `POST /reports/{id}` or `POST /v1/roots:batch` no longer forces `Connection: close`. The status and body are unchanged.
- A collector that hangs holds the exit for up to 5s more. With api's 5s settle and 20s drain, the worst case is exactly Kubernetes' default 30s grace.
- The jidhr module now has dependencies: ukubi-go and the OpenTelemetry modules it brings, a `go.sum`, and a pin that must move with server's.
- Every new gated route goes into the table, not onto a mux by hand.

## Reversibility

Cheap. Unsetting the variable turns tracing off with no deploy of code. Removing it is one `telemetry.New` per `main`, the `handle` wrappers, and the jidhr requirement. The signal to revisit is a trace backend that needs a different span shape, or propagation landing in the standard.
