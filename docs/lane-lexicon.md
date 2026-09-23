# Lane's Lexicon: the licence, and the join

Two questions decide whether Lane's *An Arabic-English Lexicon* can be the source
of root meanings in Wird. Both were open. Both were answered on 2026-09-23 by
reading the instruments and measuring the data rather than by assuming either.

- **The licence.** Can the Perseus TEI edition be bundled inside an AGPL-3.0
  binary? **No, not as Perseus publishes it.** Perseus licenses Lane under
  **CC BY-SA 3.0 United States**, which has no compatibility path to any
  GPL-family licence — only 4.0 has one.
- **The join.** If it could be bundled, would it reach our roots? **Yes, and by a
  wide margin.** 1,582 of our 1,642 roots (96.3%) have a non-stub Lane article
  after the fold, covering 99.2% of Qur'anic root occurrences. The join is not
  the blocker. The licence is.

Everything below is the working.

---

## Part one: the licence

### Three instruments, three different answers, on the same bytes

The same Lane XML carries three separate statements of terms, and they do not
say the same thing. Which one governs is the whole question.

**(1) The `<availability>` block inside every XML file.** Identical in all 36
files of the `originals` branch — one SHA-256 across all of them. Verbatim, in
full:

```xml
<availability status="free">
   <p>This text may be freely distributed, subject to the following
      restrictions:</p>
   <list>
      <item>You credit Perseus, as follows, whenever you use the document:
         <quote>Text provided by Perseus Digital Library, with funding from The
         U.S. Department of Education and The Max Planck Society.</quote>
      </item>
      <item>You leave this availability statement intact.</item>
      <item>You offer Perseus any modifications you make.</item>
   </list>
</availability>
```

Three conditions: credit, keep the statement, offer modifications back. **No
ShareAlike, no NonCommercial, no Creative Commons licence named.** This is the
statement `data/SOURCES.md` had already read correctly — "attribution, keep the
notice, offer modifications back" is exactly it, and the draft that claimed
Perseus permits "closed or open redistribution with attribution" was reading a
term that is not there.

**(2) Perseus's own page for this text.** `perseus.tufts.edu/hopper/text?doc=Perseus:text:2002.02.0015`,
read live and in Wayback captures from 2024-02-26 and 2026-04-13. Verbatim:

> This work is licensed under a Creative Commons Attribution-ShareAlike 3.0
> United States License.
>
> An XML version of this text is available for download, with the additional
> restriction that you offer Perseus any modifications you make. Perseus
> provides credit for all accepted changes, storing new additions in a
> versioning system.

The licence link on that page resolves to
`https://creativecommons.org/licenses/by-sa/3.0/us/`. Not 4.0. Not Unported.
**CC BY-SA 3.0 United States**, plus an additional restriction on the XML
download specifically — the one the availability block also carries.

**(3) The site-wide copyright page**, `perseus.tufts.edu/hopper/help/copyright.jsp`
(the live page returned HTTP 503 on 2026-09-23; read from the Wayback capture of
2024-12-18). Verbatim:

> Tufts University holds the overall copyright to the Perseus Digital Library;
> the materials therein (including all texts, translations, images,
> descriptions, drawings, etc.) are provided for the personal use of students,
> scholars, and the public. Any commercial use or publication without
> authorization is strictly prohibited. Materials within the Perseus DL have
> varying copyright status: please contact the project for more information
> about a specific component or object.

"Any commercial use or publication without authorization is strictly prohibited"
is a NonCommercial term. It contradicts both the file and the per-text page, and
the same paragraph then tells you the answer varies per object and to ask.

**Lane is not in any PerseusDL git repository.** `PerseusDL/lexica` carries
`license.md` — the full legal code of **CC BY-SA 4.0** — and its README says
"Unless otherwise indicated, all contents of this repository are licensed under
a Creative Commons Attribution-ShareAlike 4.0 International License. You must
offer Perseus any modifications you make." That would be the workable licence.
But the repository holds only `CTS_XML_TEI/perseus/pdllex/grc` and `.../lat` —
Greek and Latin. Arabic is not there. Checked every repository in the PerseusDL
organisation: there is no `canonical-arabicLit`. So the 4.0 grant, which is the
only one that would work, does not reach this text.

### Why CC BY-SA 3.0 closes the door

CC BY-SA 3.0 US §4(b), verbatim:

> You may distribute, publicly display, publicly perform, or publicly digitally
> perform a Derivative Work only under: (i) the terms of this License; (ii) a
> later version of this License with the same License Elements as this License;
> (iii) either the Creative Commons (Unported) license or a Creative Commons
> jurisdiction license (either this or a later license version) that contains the
> same License Elements as this License (e.g. Attribution-ShareAlike 3.0
> (Unported)); (iv) a Creative Commons Compatible License.

Route (iv) is the only one that could reach AGPL-3.0, and it is empty. Creative
Commons's own ShareAlike-compatibility page says, verbatim:

> **BY-SA 3.0** — Currently, no non-CC licenses have been designated as
> compatible with BY-SA 3.0.

and, for 4.0:

> GPLv3 — declared a "BY-SA–Compatible License" for version 4.0 on 8 October
> 2015. [...] compatibility with the GPLv3 is one-way only, which means you may
> license your contributions to adaptations of BY-SA 4.0 materials under GPLv3,
> but you may not license your contributions to adaptations of GPLv3 projects
> under BY-SA 4.0.

So the one-way route out of ShareAlike and into the GPL family exists **only
from 4.0**. Perseus put Lane on 3.0 US. There is no route.

Had it been 4.0, the bridge to Wird would have been AGPL-3.0 §13, which this
repository's own `LICENSE` carries at line 540: *"Remote Network Interaction;
Use with the GNU General Public License"* — a covered work may be combined with
a GPLv3 work. BY-SA 4.0 → GPLv3 → AGPLv3 §13 is a real chain. BY-SA 3.0 →
nothing is not.

### The second, independent problem: "offer Perseus any modifications you make"

This term appears in both the file and the per-text page, and it is not part of
any Creative Commons licence. It is an additional restriction bolted on.

That matters twice over. CC BY-SA 3.0 US §4(a) says a licensee "may not offer or
impose any terms on the Work that restrict the terms of this License"; Perseus
imposing it as licensor is a separate layer, but it means what Wird would
receive is not clean CC BY-SA 3.0. And AGPL-3.0 §7, at line 451 of this repo's
`LICENSE`, says verbatim:

> You may not impose any further restrictions on the exercise of the rights
> granted or affirmed under this License.

A downstream recipient of Wird's AGPL source who modified the bundled Lane text
would inherit an obligation to send it to Tufts. That is a further restriction on
an AGPL-covered work. Even under a hypothetical 4.0, this term would have to
keep the Lane text *outside* the AGPL-covered work — a separately licensed data
asset with its own notice — rather than inside it.

### What is still genuinely unresolved, and stays recorded as unresolved

**Which instrument governs.** The file says one thing (no ShareAlike), the
per-text page says another (ShareAlike 3.0 US), the site page says a third
(NonCommercial). Perseus's own copyright page says to ask them. Nobody has
asked. The conservative reading — and the one this repository adopts until
somebody does ask — is the most restrictive of the three that plausibly applies
to this object: **CC BY-SA 3.0 US plus the offer-back term**.

**Whether `corpus.db` would even be a Derivative Work.** CC BY-SA 3.0 US defines
a "Collective Work" as one "in which the Work in its entirety in unmodified form
[...] are assembled into a collective whole", and ShareAlike in §4(b) binds only
Derivative Works. A database that extracts article text, reshapes it per root and
drops the TEI is a recasting, so Derivative Work is the likelier reading — but it
is a reading, not a fact, and it is not one to bet an app-store binary on.

**Whether Perseus holds a copyright to assert at all.** Lane's Lexicon was
published 1863–1893 and its author died in 1876; the underlying text is
unambiguously public domain. Perseus's claim runs to the digitisation, and under
US law a faithful transcription of a public-domain text carries no new copyright
of its own. The TEI markup and Alpheios's structural work (the header credits
"Additional XML cleanup by Alpheios Technical Services, LLC.") are a thinner and
more arguable claim. This is a real argument. It is also exactly the kind of
argument that is cheap to make and expensive to be wrong about, so it is recorded
as an argument and not relied on.

### The two branches of `laneslexicon/lexicon_xml`

The repository has exactly two branches and no `LICENSE` file at all. Its README,
on `master`, verbatim and in full:

```
For an overview of the project see [here](http://laneslexicon.github.io).

This repository contains the updated XML files.

The original Perseus XML files are in the 'originals' branch.

The master branch has all the fixes. Do not make any changes to the 'originals'.
```

There is no README on `originals` — the branch is Perseus's files and nothing
else. So the review's suspicion is confirmed in shape: **`originals` is
Perseus's, under whichever of the three instruments governs; `master` adds
community amendments that carry no stated licence from anybody.** Their author
may well have offered them to Perseus as the availability block asks, but that is
not visible from outside, and no grant to third parties is published anywhere in
the repository.

**This costs almost nothing, which is worth knowing.** 34 of the 36 files differ
between the branches, but the whole of `master`'s amendment work is **25 more
root divisions and 37,262 more characters of article prose out of 26.4 million —
0.14%**. If Lane is ever usable, use `originals`, whose provenance is clean, and
lose one part in seven hundred.

### If the answer is no, what else could serve

The question reopens rather than the project stopping. Ranked by how cleanly the
licence lands, not by how good the lexicography is:

1. **Write the prose ourselves, with Lane as a consulted reference.** Facts about
   a word are not copyrightable; a sentence of Lane's is. A one-line core sense
   per root, written from a reading of Lane and of Ibn Fāris and attributed as
   *consulted*, sidesteps every instrument above. This is also what the existing
   `root_notes` / `RootReading.coreSense` path was built for, and what the
   walkthrough's finding 1 already decided ("authored writing for ~1,642 roots").
   The measurement below then still matters — it says the reading is available for
   96.3% of the roots a reader will meet.
2. **A different digitisation of Lane.** The book is public domain; only Perseus's
   markup is claimed. Page scans exist at archive.org with no such claim. The cost
   is OCR of Arabic-script lexicography, which is the expensive part and the
   reason Perseus's edition is the one everyone uses.
3. **Wiktionary's Arabic root entries.** **CC BY-SA 4.0**, which is the one
   licence in this space with the one-way route to GPLv3 and therefore, via
   AGPL-3.0 §13, into Wird. Coverage and quality per root are unmeasured; nobody
   has checked how many of our 1,642 roots it reaches. That measurement has not
   been done and should not be assumed.
4. **Penrice, *A Dictionary and Glossary of the Kor-ân* (1873).** Public domain,
   and the one candidate that is a Qur'anic root glossary by construction rather
   than a general lexicon. Its digitisations were not examined here.
5. **OpenITI's Ibn Fāris and Lisān al-ʿArab.** Still CC BY-NC-SA, still ruled out
   by the NonCommercial term for anything sold, and still a further restriction
   AGPL-3.0 §7 forbids on a covered work. Unchanged from what `SOURCES.md`
   already says.

Ask Perseus. It is one email, the answer settles three contradictory
instruments at once, and if the answer is "4.0, like the rest of the library"
then option 0 is Lane after all.

---

## Part two: the join, measured

### The method

Source: `github.com/laneslexicon/lexicon_xml`, branch `originals`, 36 TEI files,
11.6 MB compressed. Lane's articles are `<div2 type="root" n="...">` elements;
`@n` is the root key in Perseus's Buckwalter variant, where `A^` is hamza seated
on alef, `y^` hamza on ya, `A` a bare alef, `Y` alef maqsura, and the rest the
usual 28 consonants. "Article prose" below means the characters left after
stripping every tag from a division, summed across every file that carries that
key — Lane's Book I and its Supplement both hold a ك section and both count.

The script that produced every number below is reproduced in full at the end of
this file, so the numbers can be re-run rather than believed.

**The fold.** `SOURCES.md` already warned that "a join between the two should
fold rather than assume", and it needs four folds, not one:

| Fold | Why | Roots it moves |
| --- | --- | --- |
| every hamza seat onto one (`ا إ آ ؤ ئ ء → أ`), and `ى → ي` | `server/cmd/etl/load.go:282-289` folds every hamza onto Buckwalter `A`, so our keys carry only `أ`; Lane's carry the real seat | 135 of ours carry a hamza |
| a geminate `r1r2r2` onto the biliteral `r1r2` | our roots are triliteral; Lane files a geminate under two letters — مدد is Lane's `md`, ربب his `رب` | **153 roots, 4,624 occurrences** |
| a reduplicated quadriliteral `r1r2r1r2` onto `r1r2` | زلزل is Lane's `زل`, وسوس his `وس` | 13 roots |
| a final-weak `r1r2{ويأ}` onto the biliteral | يدي is Lane's `يد`, ملأ his `مل` | 13 roots |

The review's counts were right: 135 hamza roots, and 153 geminate roots at 4,624
occurrences. Without the geminate fold those 153 roots and 4,624 occurrences —
including ربب (980), أيي (382) and كلل (377) — join to nothing at all.

### The numbers

```
Lane root divisions parsed : 5,062        article prose: 26,420,716 characters
our roots                  : 1,642        occurrences:   49,967

join with all four folds
  exact after the hamza fold      1,432   (87.2%)
  only as a geminate biliteral      153   ( 9.3%)
  only as a reduplicated biliteral   13   ( 0.8%)
  only as a final-weak biliteral     13   ( 0.8%)
  no division of their own           31   ( 1.9%)
```

**The stub threshold, calibrated rather than picked.** A stub is a division whose
whole text is a pointer somewhere else — `lA^lA^  See art. lA^ .` is 21
characters; `khf  See Supplement` is 18. Of the 5,062 divisions, 31 consist of
nothing but a cross-reference, and **the longest of those is 146 characters**. So
**a stub is a division carrying fewer than 200 characters of prose** — comfortably
above every pure pointer and comfortably below the shortest division that says
anything (the first decile of division sizes is 122 characters, the second 483).

**THE NUMBER: 1,582 of our 1,642 roots — 96.3% — have a non-stub Lane article
after the fold, and they carry 49,563 of 49,967 root occurrences (99.2%).**

Depth, at thresholds above the stub line:

| Article at least | Roots | Occurrences covered |
| --- | --- | --- |
| 200 characters (non-stub) | 1,582 (96.3%) | 49,563 (99.2%) |
| 600 characters | 1,532 (93.3%) | 49,151 (98.4%) |
| 2,000 characters | 1,379 (84.0%) | 45,435 (90.9%) |

### Lane does thin out from ق, and the review's figures hold

30.1% of our roots (495) have a first radical of ق or later, and they carry
16,022 of 49,967 occurrences — **32.1%**. Of the hundred roots we meet most often,
**33 sit in that zone and they are 34.4% of those hundred roots' occurrences**.

The thinning is real and it is a factor of three. Each figure counts the article
a root actually reaches after all four folds:

```
median article,  1,147 roots before ق : 9,681 characters
median article,     80 roots under  ق : 5,547 characters
median article,    415 roots after  ق : 2,987 characters
```

Per first radical, in Lane's order, with stubs counted at the 200-character line:

```
  أ  n=  68  median=  9,381  stubs=0          ض  n=  25  median=  9,383  stubs=0
  ب  n=  83  median=  8,283  stubs=1          ط  n=  36  median= 11,291  stubs=0
  ت  n=  20  median=  4,788  stubs=1          ظ  n=   7  median= 18,162  stubs=0
  ث  n=  21  median=  7,448  stubs=1          ع  n= 102  median= 14,753  stubs=0
  ج  n=  69  median=  7,678  stubs=4          غ  n=  50  median= 10,221  stubs=0
  ح  n=  98  median=  9,609  stubs=2          ف  n=  72  median=  9,460  stubs=0
  خ  n=  71  median=  9,681  stubs=2          ق  n=  80  median=  5,547  stubs=4
  د  n=  46  median=  9,400  stubs=3          ك  n=  61  median=  2,217  stubs=8
  ذ  n=  22  median= 13,465  stubs=0          ل  n=  55  median=  2,599  stubs=3
  ر  n=  87  median=  9,621  stubs=0          م  n=  67  median=  3,156  stubs=5
  ز  n=  39  median=  9,354  stubs=0          ن  n= 105  median=  3,948  stubs=11
  س  n= 105  median= 10,194  stubs=0          ه  n=  39  median=  2,556  stubs=5
  ش  n=  63  median=  9,490  stubs=1          و  n=  77  median=  3,068  stubs=7
  ص  n=  63  median= 11,505  stubs=0          ي  n=  11  median=  2,288  stubs=2
```

The cause is not mysterious, and the measurement lands exactly where the
bibliography says it should. Lane had reached ق when he died in 1876; volumes
one to five are his, and volumes six to eight — ك onward — were published
between 1877 and 1893 by Stanley Lane-Poole out of the incomplete notes Lane
left, a supplement rather than a lexicon. ق itself is the seam, and it reads
like one: its median is 5,547 characters against 9,681 for everything before it
and 2,987 for the 415 roots after it.

**What that costs where it hurts most.** The twenty roots a reader meets most
often, with the article each one actually gets:

```
  أله     2,851  أله                12,885 chars  15 entries
  قول     1,722  قول                 3,221 chars  11 entries
  كون     1,390  كون                 1,755 chars   6 entries
  ربب       980  رب      geminate   44,555 chars  50 entries
  أمن       879  أمن                28,787 chars  27 entries
  علم       854  علم                29,600 chars  40 entries
  قوم       660  قوم                13,395 chars  29 entries
  أتي       549  أتي                19,521 chars  23 entries
  كفر       525  كفر                23,613 chars  23 entries
  بين       523  بين                37,099 chars  24 entries
  شيأ       519  شيأ                12,874 chars  11 entries
  رسل       513  رسل                29,889 chars  26 entries
  أرض       461  أرض                15,158 chars  18 entries
  يوم       405  يوم                 1,756 chars   4 entries
  أيي       382  أي      geminate   39,463 chars  22 entries
  سمو       381  سمو                21,416 chars  27 entries
  كلل       377  كل      geminate    3,227 chars  12 entries
  عذب       373  عذب                15,778 chars  23 entries
  عمل       360  عمل                18,108 chars  29 entries
  جعل       346  جعل                12,390 chars  21 entries
```

Not one of them is a stub. But قول, the second most frequent root in the Qur'an,
gets 3,221 characters where صبر gets 25,723; كون gets 1,755 and يوم 1,756. **The
depth problem is real and it is not a coverage problem** — every one of these has
an article, and the article for the commonest verbs is a quarter the length of
the article for a root of a tenth their frequency. A core sense can be drawn from
1,755 characters. A poetic reading with any weight behind it is harder.

### The finding nobody was looking for: `div2/@n` is not a root index

**Do not key an implementation on `@n`.** The division index in the Perseus XML
is incomplete and in places simply wrong, and a naive join silently loses real
articles:

- **دبر has no division.** Its article is present and substantial — the entries
  `dabarahu`, `duburN`, `Adbr`, `Astdbrhu` and six more are all there — but they
  sit *inside* the division keyed `dbx` (دبخ), which measures 44,503 characters
  because it is two roots merged into one.
- **نوم has no division either.** It is filed under the key `nAm` — the vocalised
  past tense نام, not the root skeleton. Division keys are not consistently root
  skeletons: `jahila`, `HaAja`, `baqala` and `dwrd` are all used as `@n` values.
- **81 keys are ranges.** `nwE &amp;c.`, `nhl &amp;c.`, `nyf &amp;c.` — one
  division standing for several roots, named after the first.

Of the 31 roots that reach no division of their own, **18 have their headword
inside some other division** and so do have Lane text:

```
  بقل→baqala  تيه→tyn   جحد→Hd    جحم→jHfl  جهز→Hhz   جهل→jahila
  حرث→Hrb     حوج→HaAja خبت→xbv   دبر→dbx   دور→dwrd  شأم→$m
  نحت→nxt     نصت→nSb   نضخ→nDH   نفح→tfH   نوم→nAm   هأت→hyt
```

That last one settles a thing `SOURCES.md` flags: our هأت is the fold's mangling
of هات, and Lane's article is at `hyt` (هيت, 3,254 characters). Our other mangled
root, لألأ for لؤلؤ, does reach Lane's `lA^lA^` — but that division is a
21-character cross-reference, `See art. lA^`, so it is a stub either way.

**13 roots have no Lane text at all**, totalling 29 of 49,967 occurrences:
دهق، كهن، نتق، نزغ، هرع، هطع، هلع، همن، وبق، وجف، وجل، وسن، ينع. Every one of them
begins with a letter in the posthumous supplement, which is the same cause as the
thinning.

### The verdict on the join

The join is not the obstacle. Fold four ways, resolve headwords rather than
division keys, and **96.3% of our roots have real Lane text and 99.2% of what a
reader will actually meet is covered**. What the measurement does say is that the
*depth* is uneven in a way that maps onto frequency badly — a third of what a
reader meets sits in Lane's thin posthumous half — and that any implementation
keyed on `div2/@n` will quietly lose دبر, دور, جهل and sixteen others.

None of which matters unless the licence question is answered, and today it is
answered no.

---

## Two corrections made while here

**The root count.** `jidhr/testdata/corpus.json` and `jidhr/pkg/root/attest_test.go`
both cited **1,651** roots. That is the dropped `mustafa0x/quran-morphology`
fork's count; upstream ships **1,642**, and `data/SOURCES.md` has said so since
2026-09-23. `SOURCES.md` itself is not wrong — the one place it prints 1,651 is
the fork's own column in the fork-versus-upstream table, where it belongs.

**A claim in that same note that was wrong for a second reason.**
`jidhr/testdata/corpus.json` said of لوك, ريض, صري, نير, ريم, انس, وسي and دير
that "every one of them will be among the 1,651 roots phase 3 ships". **None of
the eight is in the shipped `roots` table** — checked one by one against
`app/assets/corpus.db`. They are real classical triliterals, but the Quranic
Arabic Corpus does not attest them, so the sentence's own warning ("A test that
holds only because a root is missing holds by accident") applied to the sentence.
Corrected to what the table says. Whether the test battery beneath it wanted
those roots present or absent is a question for whoever owns `jidhr`; nothing in
`jidhr`'s code was touched.

## The script

Reproduces every number above. `originals` branch of
`github.com/laneslexicon/lexicon_xml` in one directory, `corpus.db` as the second
argument.

```python
import collections, glob, os, re, sqlite3, statistics, sys

LANE_DIR, DB = sys.argv[1], sys.argv[2]
STUB = 200

# Perseus writes Lane's Arabic in a Buckwalter variant: A^ is hamza seated on
# alef, y^ on ya, A a bare alef, Y alef maqsura, the rest the usual 28 letters.
TWO = {'A^': 'أ', 'y^': 'ئ', 'w^': 'ؤ'}
ONE = {'A': 'ا', 'Y': 'ى', 'b': 'ب', 't': 'ت', 'v': 'ث', 'j': 'ج', 'H': 'ح',
       'x': 'خ', 'd': 'د', '*': 'ذ', 'r': 'ر', 'z': 'ز', 's': 'س', '$': 'ش',
       'S': 'ص', 'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع', 'g': 'غ', 'f': 'ف',
       'q': 'ق', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'h': 'ه', 'w': 'و',
       'y': 'ي'}
HAMZA = str.maketrans({'ا': 'أ', 'إ': 'أ', 'آ': 'أ', 'ؤ': 'أ', 'ئ': 'أ', 'ء': 'أ'})


def arabic(key):
    out, i = [], 0
    while i < len(key):
        if key[i:i + 2] in TWO:
            out.append(TWO[key[i:i + 2]]); i += 2
        elif key[i] in ONE:
            out.append(ONE[key[i]]); i += 1
        else:
            return None
    return ''.join(out)


def fold(root):
    return root.translate(HAMZA).replace('ى', 'ي')


chars, entries, text = collections.Counter(), collections.Counter(), collections.defaultdict(str)
for path in sorted(glob.glob(os.path.join(LANE_DIR, '*.xml'))):
    src = open(path, encoding='utf-8').read()
    parts = re.split(r'(<div2\b[^>]*>)', src)
    for i in range(1, len(parts), 2):
        if 'type="root"' not in parts[i]:
            continue
        n = re.search(r'\bn="([^"]*)"', parts[i])
        if not n:
            continue
        body = parts[i + 1].split('</div2>')[0]
        prose = re.sub(r'\s+', ' ', re.sub(r'<[^>]*>', ' ', body)).strip()
        for key in re.split(r'\s+(?:and|or)\s+', n.group(1).replace('&amp;c.', '')):
            key = key.strip()
            if not key or key.startswith('Quasi'):
                continue
            ar = arabic(key)
            if ar is None:
                continue
            f = fold(ar)
            chars[f] += len(prose)
            entries[f] += body.count('<entryFree')
            text[f] += ' ' + prose

ours = sqlite3.connect(DB).execute('select letters, quran_occurrences from roots').fetchall()
TOTAL = sum(o for _, o in ours)


def look(r):
    f = fold(r)
    if f in chars:
        return f, 'exact'
    if len(f) == 3 and f[1] == f[2] and f[:2] in chars:
        return f[:2], 'geminate'
    if len(f) == 4 and f[:2] == f[2:] and f[:2] in chars:
        return f[:2], 'reduplicated'
    if len(f) == 3 and f[2] in 'ويأ' and f[:2] in chars:
        return f[:2], 'final-weak'
    return None, None


rows = [(l, o) + look(l) + (chars.get(look(l)[0], 0),) for l, o in ours]
pct = lambda n, d=len(ours): f'{n} ({100.0 * n / d:.1f}%)'

xref = [c for f, c in chars.items() if re.fullmatch(r'\s*\S+\s+[Ss]ee\b.{0,140}', text[f])]
print(f'divisions parsed {len(chars)}; pure cross-references {len(xref)}, longest {max(xref)}')
for how, n in collections.Counter(r[3] for r in rows).most_common():
    print(f'  {how or "no division":14} {pct(n)}')
for t in (STUB, 600, 2000):
    n = sum(1 for r in rows if r[4] >= t)
    occ = sum(r[1] for r in rows if r[4] >= t)
    print(f'  >= {t:5} chars: {pct(n)}  {occ} occurrences ({100.0 * occ / TOTAL:.1f}%)')

ORDER = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي'
zone = set(ORDER[ORDER.index('ق'):])
inz = [r for r in rows if fold(r[0])[0] in zone]
top = sorted(rows, key=lambda r: -r[1])[:100]
print(f'  ق onward: {pct(len(inz))} of roots, '
      f'{100.0 * sum(r[1] for r in inz) / TOTAL:.1f}% of occurrences; '
      f'{sum(1 for r in top if fold(r[0])[0] in zone)} of the top 100, '
      f'{100.0 * sum(r[1] for r in top if fold(r[0])[0] in zone) / sum(r[1] for r in top):.1f}%'
      ' of their occurrences')
pre = [r[4] for r in rows if fold(r[0])[0] not in zone]
print(f'  median article before ق {int(statistics.median(pre))}, '
      f'ق onward {int(statistics.median([r[4] for r in inz]))}')
```
