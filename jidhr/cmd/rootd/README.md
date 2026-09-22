# rootd

`rootd` serves `jidhr`, the Arabic root engine, over HTTP. Give it a written Arabic
word and it answers with the root that word comes from, the lemma and form when the
corpus records them, and the meanings authored for that root.

It is the way to use `jidhr` from outside Wird. Inside Wird the same engine is a Go
library call, and the two answer identically because they run the same resolver over
the same store.

## Running it

```bash
go run ./jidhr/cmd/rootd            # :8081, seed corpus, no key, 5 requests a second
curl 'localhost:8081/v1/root?word=وَتَوَاصَوْا&lang=en,ar'
```

| Variable | Default | What it does |
| --- | --- | --- |
| `ROOTD_ADDR` | `:8081` | listen address |
| `ROOTD_CORPUS` | `jidhr/testdata/corpus.json` | the corpus file to serve, read once at startup |
| `ROOTD_API_KEY` | unset | when set, every `/v1` call must send `Authorization: Bearer <key>` |
| `ROOTD_RATE` | `5` | requests a second per caller; the burst is four seconds' worth. `0` turns throttling off |

`GET /healthz` answers 200 and is deliberately outside both the key and the rate
limit, so an orchestrator's probe cannot be throttled into restarting a healthy
process.

## Endpoints

### `GET /v1/root?word=&lang=`

`lang` is a comma-separated list, `en,ar` by default. Those are the two languages
meanings are authored in; asking for anything else returns no meanings in it rather
than an error.

```json
{
  "input": "وَتَوَاصَوْا",
  "normalized": "وتواصوا",
  "root": { "letters": "وصي", "display": "و ص ي", "translit": "w-ṣ-y" },
  "lemma": "تَوَاصَى",
  "form": "VI · perfect · 3rd m. pl.",
  "method": "lexicon",
  "quran": { "occurrences": 32 },
  "meanings": { "en": { "plain": "…", "poetic": "…" }, "ar": { "plain": "…" } }
}
```

`normalized` is the input with its orthography regularised — no diacritics, one
alef, one ya, one ha. It is the spelling the corpus is keyed by, not the stem the
affix stripper produced.

`quran` is **absent** when the root does not occur in the Qur'an. It is not zero,
because zero is a measurement and absence is the truth. Likewise a `poetic` meaning
nobody has written yet is absent rather than empty.

### `POST /v1/roots:batch`

```bash
curl -X POST 'localhost:8081/v1/roots:batch?lang=en' -d '{"words":["صَبَرُوا","مكتوب"]}'
```

At most **100 words** per call; a longer list is refused whole, with nothing
resolved, so a caller can never be left guessing which of its words were dropped.

Each word answers for itself:

```json
{"results":[
  {"input":"صَبَرُوا","result":{ … }},
  {"input":"hello","error":{"status":400,"code":"not_arabic","message":"…"}}
]}
```

One unresolvable word does not sink the batch. A corpus failure does: partial
results from a broken corpus look complete, so the whole call fails with 500
instead.

### `GET /v1/roots/{letters}`

`letters` is the **joined** form — `وصي`, percent-encoded — never the spaced
`display` form. One key, encoded one way, by every caller.

```json
{
  "root": { "letters": "وصي", "display": "و ص ي", "translit": "w-ṣ-y" },
  "quran": { "occurrences": 32 },
  "meanings": { "en": { … } }
}
```

## `method` — which rung answered

The resolver walks five rungs and stops at the first that hits. `method` names that
rung, and the rung **is** the confidence: it tells you how the answer was reached, so
you can decide what to trust. There is no `confidence` field, because a float nobody
defined is something callers branch on without knowing what they are branching on.

| `method` | What happened | How much to trust it |
| --- | --- | --- |
| `lexicon` | The word was found spelled exactly as you sent it, diacritics and all. | An attested corpus fact. |
| `normalized` | Found after regularising the orthography. | The same fact, reached past a spelling difference. |
| `lemma` | The dictionary form was found rather than this inflection. | The corpus knows the word; it had not written down this spelling. |
| `stripped` | Prefixes and suffixes were peeled off, and the stem was found. | A derivation. Which affixes were peeled is a judgement. |
| `pattern` | Nothing was found; the radicals were read out of the word's shape by matching it against the standard templates. | A derivation from form alone. Correct for regular words, and it is the rung that lets a word outside the Qur'anic corpus resolve at all. |

## Errors

The body is always `{"error": {"status": …, "code": …, "message": …}}`, and a 404
also carries `candidates`: the forms the ladder actually tried.

| Status | `code` | Means |
| --- | --- | --- |
| 400 | `not_arabic` | What you sent is not an Arabic word. Fix the input. |
| 400 | `missing_word` | The `word` parameter never arrived. |
| 400 | `batch_too_large` | More than 100 words in one batch. |
| 400 | `bad_body` | The batch body is not `{"words": […]}`. |
| 401 | `unauthorized` | A key is configured and yours did not match. |
| 404 | `no_root` | Good Arabic, no derivable root — with the candidates considered. |
| 429 | `rate_limited` | Slow down; `Retry-After` says how long. |
| 500 | `internal` | We failed. Nothing about your word is implied. |

**400 and 404 are different answers on purpose.** 400 says the input was wrong; 404
says the input was fine and we do not know the word. A service that returns 404 for
both teaches every caller to keep sending garbage.

A 500 is never a statement about the word. If the corpus is unreachable you get 500,
not a 404 that says the word has no root.

## What it cannot do

- **It does not read context.** One word in, one root out. An Arabic homograph that
  means two things depending on the sentence around it gets one answer, and it is
  whichever the corpus indexed first.
- **The `pattern` rung can be wrong.** It derives radicals from shape. A word whose
  shape resembles a template but is not built from one gets a plausible root that is
  not real. It refuses to guess when no template fits — that is a 404 — but it cannot
  detect a template that fits by accident.
- **It has no transliteration for a root it has never recorded.** A root the pattern
  rung derives from outside the corpus carries `letters` and `display` but an empty
  `translit`.
- **Meanings exist in `en` and `ar` only**, and only for roots somebody has written
  them for. They are authored, never generated, so a root with nothing written yet
  comes back with no `meanings` at all rather than with a machine translation.
- **The corpus is Qur'anic.** Modern vocabulary resolves through the `stripped` and
  `pattern` rungs when its shape is regular, and misses when it is not. It is not a
  dictionary of Modern Standard Arabic.
- **It serves one corpus file, read into memory at startup.** There is no reload, no
  pagination, and no search: you look up a word or a root you already have.
- **It terminates no TLS and knows no users.** The API key is one shared secret, all
  or nothing, and callers are told apart for rate limiting by their network address —
  behind a proxy, every caller looks like the proxy. Put it behind something that
  handles TLS and identity if either matters to you.
