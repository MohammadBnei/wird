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

Five questions, five different answers — this is the whole service:

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

# A spelling two roots share, typed without the diacritics that tell them apart.
# 200, every root the corpus records for it, most-used first.
curl -sG localhost:8081/v1/root --data-urlencode 'word=قل'
{"input":"قل","normalized":"قل","root":{"letters":"قول","display":"ق و ل","translit":"q-w-l"},
 "roots":[{"letters":"قول","display":"ق و ل","translit":"q-w-l"},
          {"letters":"قلل","display":"ق ل ل","translit":"q-l-l"}],
 "method":"shared","quran":{"occurrences":1722}, …}

# The same word with the diacritics the corpus writes. One root, and method lexicon.
curl -sG localhost:8081/v1/root --data-urlencode 'word=قُلْ'
{"input":"قُلْ","normalized":"قل","root":{"letters":"قول","display":"ق و ل","translit":"q-w-l"},
 "method":"lexicon","quran":{"occurrences":1722}, …}
```

The second answer is the one to read twice. **A root with nothing written is not an
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
| attested forms | 17,934 written spellings, each under the root the morphology records it under |
| rootless forms | 1,189 written spellings the morphology records under no root at all |
| meanings | 523 roots, in `en` and `fr`, plain register |
| roots with no meaning | 1,119 |

The roots and the forms are the Quranic Arabic Corpus morphology. **The meanings are
Wird's own reading of each root**, written from that root's own words in the Qur'an
and kept only where their glosses bore it out — not quoted from a lexicon, and never
generated. That is why 1,119 roots carry nothing: a sense that the root's own words
did not bear out was refused rather than softened.

### What resolves, and what does not

Every one of the 17,934 forms answers with the root the morphology records for it
when you send it spelled as the corpus spells it. Typed without diacritics, 17,653
of them answer with one root and 281 answer with the readings that spelling is shared
between — 57 of those because the spelling is shared with a particle that has no
root. None miss, and none come back under a root the corpus does not record for that
spelling.

2,480 of those forms are written with a dagger alef — the superscript `ٱلْعَـٰلَمِينَ`
carries, standing for a long ā that Uthmani orthography does not spell out. Each of
them is indexed twice, under the spelling with that alef dropped and under the
spelling with it written, so `العالمين` and `ٱلْعَـٰلَمِينَ` are the same word here and
`الرحمن` and `ٱلرَّحْمَـٰنِ` are too. In the database those 2,480 are 2,791 rows, because a
form written twice with different recitation marks is two rows there and one form
here.

Indexing them once was the defect: **every one of these was a miss for a caller
who typed the ordinary spelling**, and Al-Fatiha is mostly these words —
`العالمين`, `مالك`, `الصراط`, `الإنسان`. Counting exactly how many were
unreachable turns on which of two sibling fixes you hold out and on whether
"reachable" means the right root or any answer at all; the reconstructions land
between 2,687 and 2,721 and no single number is the number. What is measurable
from the tree as it stands is the part that matters: **of the 2,480, none miss,
in either spelling.**

Three things are still out of reach, and they are what "a Qur'anic word resolves"
does not cover:

- **Three forms that are two words in one row.** `بَعْدَ مَا` and two others are stored
  with a space inside them and are reachable only by typing that space.
- **Two Uthmani spellings that are not reduced.** `ءامنوا` does not reach `آمنوا`, and
  `صلوة`, `زكوة`, `حيوة` do not reach `صلاة`, `زكاة`, `حياة`.
- **Three spellings the corpus itself leaves open.** `أَسْرَىٰ`, `أَهْلَكَ` and `عَادٍۢ` are
  written identically under two roots, diacritics and all. They answer with both
  (see `shared` below), because the morphology does not settle them and neither may
  we.

`jidhr/testdata/corpus.json` is the other corpus here: 44 roots, four meanings, two
rootless spellings, and the worked example to copy if you want to hand `jidhr` a
corpus of your own. Point `ROOTD_CORPUS` at it to see the shape a corpus file has.

### The words that have no root

1,492 of the form rows carry no root at all — `مِنْ`, `هُوَ`, `ٱلَّذِينَ`, `لَمْ`, `عَلَيْهِمْ`,
the pronouns and the particles, 1,189 written spellings once the recitation marks
are off. The morphology records them that way deliberately: a particle does not come
from a triliteral root. The corpus ships them, so asking about one gets the
authority's own answer instead of a guess.

```bash
# A word the corpus records with no root. 404, code rootless, and no candidates.
curl -sG localhost:8081/v1/root --data-urlencode 'word=مِنْ'
{"error":{"status":404,"code":"rootless",
 "message":"the corpus records \"مِنْ\" with no root: it is a particle or a pronoun, and comes from none"}}

# The same letters typed bare. They are the particle, and they are also مَنَّ, which is منن.
curl -sG localhost:8081/v1/root --data-urlencode 'word=من'
{"input":"من","normalized":"من","root":{"letters":"منن","display":"م ن ن","translit":"m-n-n"},
 "roots":[{"letters":"منن","display":"م ن ن","translit":"m-n-n"}],
 "rootless":true,"method":"shared","quran":{"occurrences":27}, …}
```

`rootless` and `no_root` are both 404 and they are not the same answer. `no_root`
says the corpus does not know the word, so grow the corpus or ask elsewhere.
`rootless` says the corpus knows the word perfectly well and records it as coming
from no root, which is the end of the question — and it carries no `candidates`,
because nothing was considered.

Until those spellings shipped, **139 of the 1,492** were answered with a root the
morphology denies them. `مِنْ` came back `منن` and `عَلَيْهِمْ` came back `علو`, because
`مَنَّ` and `عَـٰلِيَهُمْ` are spelled that way once the diacritics are gone and only the
forms that have a root were in the file. Those answers came back as
`method: "pattern"`, which the table below calls an attested corpus fact, with
nothing to mark them. The dagger-alef and the pause-mark fixes widened the class
rather than narrowing it: both made spellings reachable that had reached nothing
before, and some of what they reached was this.

### Languages

`en` and `fr`, because those are the two the 523 meanings are written in. There is no
list of languages configured anywhere: a caller that names no `lang` is answered in
whatever languages the loaded corpus actually holds, and `rootd` logs them at startup.

A tag is read case-insensitively: `lang=EN` and `lang=en` are one language.

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
#   roots 1642  attested forms 17934  rootless forms 1189  roots with a meaning 523  languages [en fr]
#   0.80 MB
```

`-db` and `-out` move either end. Editing the JSON by hand puts it out of step with
the database the app reads, and the next rebuild silently reverts you.

## Endpoints

### `GET /v1/root?word=&lang=`

`lang` is a comma-separated list. Omit it for every language the corpus has; name one
to get only that one. A language nobody wrote returns no meanings in it rather than an
error.

`normalized` is the input with its orthography regularised — no diacritics, one alef,
one ya, one ha — and with the pause, sajda and section marks of the recitation taken
off. It is the spelling the corpus is keyed by, not the stem the affix stripper
produced. A word written with a dagger alef is keyed twice, so both the Uthmani
spelling and the ordinary one reach it.

`quran` is **absent** when the root does not occur in the Qur'an. It is not zero,
because zero is a measurement and absence is the truth.

`rootless` is **present and true** only when the corpus also records the spelling you
sent under no root at all, and it always comes with `method: "shared"` over this corpus. It is the
reading `roots` has no way to carry: `من` is `منن`, "he bestowed", and it is also the
particle, and which of the two you meant is your sentence's to say.

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
| `lexicon` | The word was found spelled exactly as you sent it, diacritics and all — as a lexicon entry, or as a spelling the corpus attests under one root where the spelling without diacritics is shared. | An attested corpus fact about the spelling you sent. |
| `normalized` | Found after regularising the orthography. | The same fact, reached past a spelling difference. |
| `lemma` | The dictionary form was found rather than this inflection. | The corpus knows the word; it had not written down this spelling. |
| `stripped` | Prefixes and suffixes were peeled off, and the stem was found. | A derivation. Which affixes were peeled is a judgement. |
| `pattern` | The corpus attests this very spelling under exactly one root. | An attested corpus fact about this spelling. |
| `shared` | The spelling you sent is one the corpus records under more than one reading, and you wrote it without the diacritics that tell them apart. `roots` carries every root it records, and `root` is the first; `rootless` says one of the readings is a particle or pronoun with no root, which `roots` cannot hold. | An attested corpus fact about the spelling, and no claim about which reading this word is. |

The Qur'anic corpus answers almost everything at `pattern`, because it records which
root each written form belongs to rather than a lexicon of entries: the first four
rungs have nothing to match against and the fifth has the attestation. The name is the
rung's, not the method's — templates rank what a **miss** reports and decide nothing.
A form the corpus never wrote down stays a miss however neatly it fits a template,
which is why `تلفزيون` and `باريس` are 404s.

A form two roots both claim is neither decided nor refused. `أسرى` is `أسر` and `سري`,
and the answer carries both under `roots` with `method: "shared"` — a 404 that listed
both readings as known and then served neither told a reader less than the corpus
knows. Diacritics settle it where the corpus writes them: `قل` is the spelling of both
`قول` and `قلل`, but `قُلْ` is written under `قول` alone, so a caller who sends the
diacritics gets that one root and `method: "lexicon"`. They do not settle `يَحْيَىٰ`,
which the corpus writes identically as the name, which has no root, and as "he
lives", which is `حيي`: that answer is `shared` with `rootless: true`, diacritics and
all.

**`roots` is ordered by how much of the Qur'an is built on each root — counted over
the whole book, not over the spelling you sent.** `كفوا` leads with `كفف`, which the
Qur'an is built on 15 times against `كفأ`'s once, though the single verse that writes
`كفوا` — 112:4 — is the `كفأ` one. Both roots are on the answer either way, and the
order ranks the roots rather than reads your word.

## Errors

The body is always `{"error": {"status": …, "code": …, "message": …}}`, and a 404 also
carries `candidates`: the forms the ladder actually tried, the ones the corpus knows
as roots first, each marked with `known`.

| Status | `code` | Means |
| --- | --- | --- |
| 400 | `not_arabic` | What you sent is not an Arabic word: no Arabic letter in it, or a letter from another script mixed in, as in `صبرabc`. Fix the input. |
| 400 | `missing_word` | The `word` parameter never arrived. |
| 400 | `batch_too_large` | More than 100 words in one batch. |
| 400 | `bad_body` | The batch body is not `{"words": […]}` — including a body that never names `words` at all. |
| 401 | `unauthorized` | A key is configured and yours did not match. |
| 404 | `no_root` | Good Arabic, no derivable root — with the candidates considered. |
| 404 | `rootless` | Good Arabic the corpus records as coming from no root: a particle or a pronoun. No candidates, because nothing was considered. |
| 429 | `rate_limited` | Slow down; `Retry-After` says how long. |
| 500 | `internal` | We failed. Nothing about your word is implied. |

**400 and 404 are different answers on purpose.** 400 says the input was wrong; 404
says the input was fine. A service that returns 404 for both teaches every caller to
keep sending garbage. The two 404 codes are different answers too: `no_root` is the
corpus coming up empty, `rootless` is the corpus answering.

A 500 is never a statement about the word. If the corpus is unreachable you get 500,
not a 404 that says the word has no root.

## What it cannot do

- **It does not read context.** One word in, one root out. An Arabic homograph that
  means two things depending on the sentence around it is answered from the one root
  the corpus records for that spelling, or — when the spelling is shared and you sent
  no diacritics — with every root the corpus records for it, and with `rootless` when
  one of the readings has none. Which one the sentence meant is the sentence's to
  say, and nothing here reads a sentence.
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
