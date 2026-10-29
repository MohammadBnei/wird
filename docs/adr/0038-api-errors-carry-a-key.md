# 38. API errors carry a key from one registry

Date: 2026-10-29. Status: accepted.

## Context

wird-api answered every JSON error as `{"error": "<reason>"}` through `httpx.Error`, from 14 sites. `/models/` and `/download/android` answered in plain text through `http.Error`, from 4 more, two of them with a 502. The reason was the only thing a client could read, so a client that wanted to tell two errors apart had to match words that were written for people.

The ukubi Code Standard gives every service one error body: ukubi-go's `errs`, `{code, key, message, source, detail}`, with the HTTP status that Connect's table gives the code, and keys from one closed registry per app.

`/v1/sync` answers per op with `{client_op_id, status, reason}`. Installed apps parse `reason` as a string ([outbox.dart:62](../../app/lib/data/outbox.dart#L62)) and branch on `status` only. A body the JSON decoder refused passed the decoder's text through as the reason, for example `json: cannot unmarshal string into Go struct field .ayah_ids of type int`, which names Go types.

The app branches only on HTTP status and op status. The public page branches on one status: `HEAD /download/android` answering 503 shows "not published yet", and anything else shows "cannot be reached" ([site/README.md](../../server/internal/site/README.md)).

## Decision

- Every wird-api error is ukubi-go's body, written by `errs.Write` through `httpx.Error(w, code, key, message)`. The message keeps the words each site used before. `source` and `detail` are empty: wird-api passes on no other service's errors. A 500 carries ukubi-go's `internal` key.
- Every key is a constant in `server/internal/keys/keys.go`. `server/errkeys_test.go` runs ukubi-go's `errkeys` analyzer over the module. A key made anywhere else fails it, and so does a registry with no key.
- `/models/` and `/download/android` use the same JSON body. Their presign failures move from 502 to 500, keyed `models.unreachable` and `apk.unreachable`. Presigning fails only when the configured endpoint does not parse, which is this server misconfigured. 503 stays "nothing published here", because the public page reads it that way.
- Each refused or failed op result gains a `key` beside `reason`. `reason` stays a string with the same words, except that a body the decoder refuses now says "the op body is not shaped like this kind" instead of the decoder's text.
- The sign-in page, the static 404s, the router's own 404 and 405 (Go's `ServeMux` answers a path or method no route serves before any handler runs) and adminweb's gate refusals stay plain text, as the standard allows.
- adminweb's triage stays plain text, but a JSON body its decoder refuses is answered "the body is not a triage" rather than the decoder's text, which quoted the caller's fields back.

## Alternatives

- **Keep an `error` field beside the new ones for old clients.** No client reads it: the app branches on status, and the page on one status. A second copy of the message would have to be kept in step for nobody.
- **503 for a presign failure, since `errs` has no 502.** The public page would then tell visitors the build is not published when the server is misconfigured.
- **One key per `refuse` call.** Thirteen keys for one decision a client can make. The six op keys say what a client can do differently: fix the kind, the body, a value, the reference, the conflict, or retry.
- **Keep the decoder's text in the reason.** It only echoes the device's own body, but it names the server's Go types and fields, and the standard asks that a client is told what it did wrong, not how the server is built.

## Consequences

- A new error needs a key in `keys.go`, and the test fails until it has one.
- A client may branch on `key`. A message may be reworded without breaking anyone.
- A browser that follows the page's Download button to a deployment with no build sees JSON instead of a sentence.
- `server/go.mod` requires ukubi-go and lists `ukubicheck` as a tool. That raises `golang.org/x/text`, which `cmd/etl` uses, from 0.41.0 to 0.42.0.
- adminweb's JSON exports and jidhr's `rootd` still answer their own error shapes. They have no caller outside their operators, and they move in a later change.

## Reversibility

Cheap on the server: `httpx.Error` is one function. Hard once a client branches on a key, because a key then cannot change meaning. A reason to undo it would be a client that needs the old `error` field, and none exists.
