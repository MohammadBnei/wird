# 39. Logs are JSON lines on stdout, and a SIGTERM drains

Date: 2026-10-29. Status: accepted.

## Context

wird-api and wird-adminweb logged through slog's default handler: text lines (`2026/10/29 01:00:00 ERROR config refused err=…`) on stderr. rootd logged JSON, also on stderr, except one line that bypassed its logger. The six CLIs used `log.Fatalf` or `fmt.Fprintln(os.Stderr, …)`.

Loki reads these lines through Alloy, which tails both streams of every pod and labels them with `namespace` and `pod`. The platform alert `log-error-rate-spike` counts lines whose detected level is `error` per pod. On a text line that level is a guess from the words. fleet core's Loki reader filters with `| json | level="…"`, which matched nothing on wird's text lines.

Both servers called `http.ListenAndServe`: no timeouts, no `ErrorLog`, and no shutdown. A rollout's SIGTERM killed the process mid-request, and the deferred `db.Close` never ran. net/http's own lines, a handler panic among them, went through the log package at no level.

The ukubi Code Standard §7 rules logs as one JSON object per line on stdout with a deliberate level, ERROR sites pinned by a test, `http.Server.ErrorLog` at ERROR, and a drain before shutdown.

## Decision

- The first statement of every `main` installs the JSON logger with `slog.SetDefault`. The services log on stdout. A CLI logs on stderr, because its stdout is its report. api, adminweb and the CLIs use ukubi-go's `telemetry.NewLogger`, which adds trace ids once spans exist. rootd uses the same handler shape, `slog.NewJSONHandler(os.Stdout, nil)`, so the jidhr module keeps no dependencies.
- Levels are deliberate. ERROR means something on our side failed. A failure whose cause is the client going away (a cancelled request context, a failed write) is WARN with the same words. A refusal of client input is INFO. `log.Fatal` is an ERROR line and `os.Exit(1)`.
- Both servers go through `httpx.Serve` ([serve.go:36](../../server/internal/httpx/serve.go#L36)): timeouts of 10s to read the header, 30s to read, 60s to write and 120s idle, `ErrorLog` at ERROR, and on SIGTERM 5s more of answering while the pod leaves its endpoints, then a drain of up to 20s, together under Kubernetes' default 30s grace. rootd keeps its own timeouts and carries a copy of the drain, without the 5s: nothing deploys it. A request's context is never tied to the signal.
- `server/logs_test.go` type-checks both modules and pins every ERROR site with its words, bans the log package, checks every `http.Server` has its `ErrorLog`, and checks each `main`'s first statement.

## Alternatives

- **Keep stderr** — Alloy reads both streams, so nothing breaks, but the standard puts every app's logs on stdout, and a CLI's stdout is the one place that must stay clean.
- **Push logs over OTLP** — the alerts and fleet core's reads select on the `namespace` and `pod` labels that file tailing adds. A pushed line has neither.
- **ERROR for every failed request** — a phone that drops mid-sync would count toward `log-error-rate-spike` as if the server had failed.

## Consequences

- Loki takes each line's level from its JSON field, so the error-rate alert counts exactly the pinned ERROR sites. Moving a line to or from ERROR changes `TestErrorSites` in the same PR.
- A rollout no longer cuts requests in flight. api's maintenance loops stop at the signal, and a sweep in flight commits before `db.Close`, or is cancelled 20s after the signal. A SIGTERM during startup lets startup finish, then drains at once.
- A `/v1/sync` upload slower than about 35 KB/s is cut at 30s. The body is at most 1 MiB.
- Message words stay an interface: a Loki query or alert that matches them must change with them.

## Reversibility

Cheap. The logger is one line per `main`, and the timeouts are constants in `httpx.Serve`. The signal to revisit them is a client whose legitimate request runs past a timeout, or an alert that needs a level the guards forbid.
