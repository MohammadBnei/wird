# rootd

`rootd` serves `jidhr`, the Arabic root engine, over HTTP. Give it a written Arabic
word and it answers with the root that word comes from, how often the Qur'an uses
that root, and the meaning somebody wrote for it.

It is the way to use `jidhr` from outside Wird. Inside Wird the same engine is a Go
library call, and the two answer identically because they run the same resolver over
the same corpus.

## Running it

You need Go and a clone of this repository. Nothing else — no database, no network,
no key. The corpus is a file in the repository and is read into memory at startup.

```bash
go run ./jidhr/cmd/rootd    # :8081, the Qur'anic corpus, no key, 5 requests a second
```

It logs what it loaded, including the languages that corpus holds meanings in:

```json
{"level":"INFO","msg":"rootd listening","addr":":8081","corpus":"jidhr/testdata/quran.json","languages":["en","fr"],"authenticated":false,"rate_per_second":5}
```

Three questions, three different answers — this is the whole service:

```bash
# A word whose root has a meaning written for it.
curl -sG localhost:8081/v1/root --data-urlencode 'word=صَبَرُوا'
{"input":"صَبَرُوا","normalized":"صبروا","root":{"letters":"صبر","display":"ص ب ر","translit":"ṣ-b-r"},
 "method":"pattern","quran":{"occurrences":103},
 "meanings":{"en":{"plain":"to be patient; to be steadfast; to endure"},
             "fr":{"plain":"être patient ; être constant ; endurer"}}}

# A word whose root has none. 200, the root, and no meanings key at all.
curl -sG localhost:8081/v1/root --data-urlencode 'word=وَتَوَاصَوْا'
{"input":"وَتَوَاصَوْا","normalized":"وتواصوا","root":{"letters":"وصي","display":"و ص ي","translit":"w-ṣ-y"},
 "method":"pattern","quran":{"occurrences":32}}

# Good Arabic that has no root here. 404, with what the ladder tried.
curl -sG localhost:8081/v1/root --data-urlencode 'word=إسطنبول'
{"error":{"status":404,"code":"no_root","message":"no root could be derived for \"إسطنبول\"",
 "candidates":[{"letters":"إسطنبول","known":false},{"letters":"اسطنبول","known":false},{"letters":"سطنبول","known":false}]}}
```

The middle answer is the one to read twice. **A root with nothing written is not an
error and not an empty meaning: the `meanings` key is absent.** 1,119 of the 1,642
roots are like that, and telling them apart from the 404 above is the whole point of
the two shapes.

| Variable | Default | What it does |
| --- | --- | --- |
| `ROOTD_ADDR` | `:8081` | listen address |
| `ROOTD_CORPUS` | `jidhr/testdata/quran.json` | the corpus file to serve, read once at startup |
| `ROOTD_API_KEY` | unset | when set, every `/v1` call must send `Authorization: Bearer <key>` |
| `ROOTD_RATE` | `5` | requests a second per caller; the burst is four seconds' worth. `0` turns throttling off |

`GET /healthz` answers 200 and is deliberately outside both the key and the rate
limit, so an orchestrator's probe cannot be throttled into restarting a healthy
process.

## What is in the corpus

`jidhr/testdata/quran.json`, the default, is the Qur'anic corpus:

| | |
| --- | --- |
| roots | 1,642, each with its transliteration and its Qur'anic occurrence count |
| attested forms | 19,805 written spellings, each under the root the morphology records it under |
| meanings | 523 roots, in `en` and `fr`, plain register |
| roots with no meaning | 1,119 |

The roots and the forms are the Quranic Arabic Corpus morphology. **The meanings are
Wird's own reading of each root**, written from that root's own words in the Qur'an
and kept only where their glosses bore it out — not quoted from a lexicon, and never
generated. That is why 1,119 roots carry nothing: a sense that the root's own words
did not bear out was refused rather than softened.

`jidhr/testdata/corpus.json` is the other corpus here: 44 roots, four meanings, and
the worked example to copy if you want to hand `jidhr` a corpus of your own. Point
`ROOTD_CORPUS` at it to see the shape a corpus file has.

### Languages

`en` and `fr`, because those are the two the 523 meanings are written in. There is no
list of languages configured anywhere: a caller that names no `lang` is answered in
whatever languages the loaded corpus actually holds, and `rootd` logs them at startup.

Asking for a language nobody wrote — `lang=ar` today — is not an error. You get the
root, and no meanings. If you need to know what is on offer before you ask, the
startup log and `GET /v1/roots/{letters}` both tell you.

### The poetic register

`Meaning` has two registers, `plain` and `poetic`. **Every meaning that ships is
plain.** Nobody has written the poetic voice yet, and an unwritten register is absent
from the JSON rather than present and empty, so a screen renders no section instead of
a blank one.

## Rebuilding the corpus

The corpus file is generated from `app/assets/corpus.db`, the checked database the
Flutter app bundles. Edit the database — through `server/cmd/etl`, which refuses a
sense the root's own words no longer bear out — then rebuild:

```bash
go run ./server/cmd/jidhrcorpus
# ./jidhr/testdata/quran.json
#   roots 1642  attested forms 19805  roots with a meaning 523  languages [en fr]
#   0.85 MB
```

`-db` and `-out` move either end. Editing the JSON by hand puts it out of step with
the database the app reads, and the next rebuild silently reverts you.

## Endpoints

### `GET /v1/root?word=&lang=`

`lang` is a comma-separated list. Omit it for every language the corpus has; name one
to get only that one. A language nobody wrote returns no meanings in it rather than an
error.

`normalized` is the input with its orthography regularised — no diacritics, one alef,
one ya, one ha. It is the spelling the corpus is keyed by, not the stem the affix
stripper produced.

`quran` is **absent** when the root does not occur in the Qur'an. It is not zero,
because zero is a measurement and absence is the truth.

### `POST /v1/roots:batch`

```bash
curl -s -X POST 'localhost:8081/v1/roots:batch?lang=en' -d '{"words":["صَبَرُوا","hello"]}'
{"results":[
  {"input":"صَبَرُوا","result":{"input":"صَبَرُوا","normalized":"صبروا","root":{"letters":"صبر", …}, …}},
  {"input":"hello","error":{"status":400,"code":"not_arabic","message":"the word is not Arabic"}}]}
```

At most **100 words** per call; a longer list is refused whole, with nothing resolved,
so a caller can never be left guessing which of its words were dropped.

One unresolvable word does not sink the batch. A corpus failure does: partial results
from a broken corpus look complete, so the whole call fails with 500 instead.

### `GET /v1/roots/{letters}`

`letters` is the **joined** form — `صبر`, percent-encoded — never the spaced `display`
form. One key, encoded one way, by every caller.

```bash
curl -s "localhost:8081/v1/roots/%D8%B5%D8%A8%D8%B1?lang=fr"
{"root":{"letters":"صبر","display":"ص ب ر","translit":"ṣ-b-r"},"quran":{"occurrences":103},
 "meanings":{"fr":{"plain":"être patient ; être constant ; endurer"}}}
```

A root the corpus does not record is a 404. A root it records with nothing written is
a 200 with no `meanings`.

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
| `pattern` | The corpus attests this very spelling under exactly one root. | An attested corpus fact about this spelling. |

The Qur'anic corpus answers almost everything at `pattern`, because it records which
root each written form belongs to rather than a lexicon of entries: the first four
rungs have nothing to match against and the fifth has the attestation. The name is the
rung's, not the method's — templates rank what a **miss** reports and decide nothing.
A form the corpus never wrote down stays a miss however neatly it fits a template,
which is why `تلفزيون` and `باريس` are 404s, and a form two roots both claim (`أسرى`
is `أسر` and `سري`) is a miss carrying both rather than a coin toss.

## Errors

The body is always `{"error": {"status": …, "code": …, "message": …}}`, and a 404 also
carries `candidates`: the forms the ladder actually tried, the ones the corpus knows
as roots first, each marked with `known`.

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
  means two things depending on the sentence around it is either answered from the one
  root the corpus records for that spelling, or reported as a miss carrying both.
- **It has no lemmas.** The corpus records a root per written form, not a dictionary
  entry, so `lemma` and `form` are absent from every answer it gives. They are in the
  response shape because a corpus that has them can fill them.
- **It has no transliteration for a root it has never recorded.** A root the pattern
  rung derives from outside the corpus carries `letters` and `display` but no
  `translit`.
- **Meanings exist in `en` and `fr` only**, plain register, for 523 of 1,642 roots.
  They are authored, never generated, so a root nobody has written for comes back with
  no `meanings` at all rather than with a machine translation.
- **The corpus is Qur'anic.** A modern word resolves only if the Qur'an happens to
  attest its spelling. It is not a dictionary of Modern Standard Arabic, and growing
  the corpus does not make `باريس` answerable.
- **It serves one corpus file, read into memory at startup.** There is no reload, no
  pagination, and no search: you look up a word or a root you already have.
- **It terminates no TLS and knows no users.** The API key is one shared secret, all or
  nothing, and callers are told apart for rate limiting by their network address —
  behind a proxy, every caller looks like the proxy. Put it behind something that
  handles TLS and identity if either matters to you.
