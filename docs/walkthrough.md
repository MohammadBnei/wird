# Walkthrough notes

Observations from using the app, collected before building, so the gaps get
addressed as gaps rather than patched one at a time.

Status: open — being filled during a walk of the app.

## Findings

### 1. The root screen shows no sense, poetic or plain

**Where:** 3a root dial, 2b spine, 1c constellation.

**What:** a root renders as letters, transliteration and an occurrence count.
The design shows a core sense and a poetic reading beside them — "To bind
fast; to hold a thing to its place. Patience is the rope, not the mood."

**Why:** `corpus.db`'s `roots` table is `letters, display, translit,
quran_occurrences, sources` and carries no sense text at all, because it is
built from the Quranic Arabic Corpus — a grammatical annotation (root, lemma,
part of speech, form), not a dictionary. It says a word's root is ص ب ر and
never what ص ب ر means. The design's own poetic lines were authored for the
mockup. `jidhr` has the table waiting (`register IN ('plain','poetic')`, per
language) but no content, and the app never calls `jidhr` — root lookup reads
the bundled corpus so it cannot touch the network.

**Shape of the gap:** authored writing for ~1,642 roots, plus a pipeline to
carry it into the bundled corpus. Decided: draft the roots a reader actually
meets first, from public-domain lexicons, with the plain gloss as the fallback
elsewhere.

**Guardrail:** the poetic register is lexicography with a voice, not tafsir. A
claim about the word, never about the verse.

### 2. An aya reference is printed everywhere and navigable almost nowhere

**Where:** 3a kin rows, 3a detail card, 1c constellation nodes.

**What:** kin rows and constellation nodes show `2:153`, `30:60`, `THIS AYA ·
103:3` as captions. The kin rows' `onTap` only moves the dial
(`root_sections.dart:153`); the constellation nodes have no gesture at all.
The one wired control, "Read the aya" (`root_screen.dart:246`), pushes 1c —
the three-pane analysis — when a reader who taps 2:153 wants to read 2:153.

**Why it stopped there:** nobody had answered what happens to the reading walk
when a reader visits an arbitrary aya. The plan's acceptance rows never
covered it and the design draws no such screen.

**Decided:** 1a shows the visited aya with no second mode. The walk position is
derived ("the next aya not yet understood in the chosen order"), so visiting
costs nothing, marking a visited aya understood counts normally, and the walk
recomputes correctly afterwards.

### 3. A reader cannot open the sūra or aya they want

**Where:** nowhere — there is no index, no sūra list, no "go to" anywhere in
the app.

**What:** the app is a walk. It hands the reader the next unread set and that
is the only way in. A reader who wants Al-Fātiḥa, or the aya they were thinking
about, or to show someone a passage, cannot reach it.

**Why it is missing:** every screen in the design is downstream of the walk —
1a serves the current set, 1d reports on it, 1e lists what was kept from it.
The design draws a sūra list nowhere. Its one hint is 1d's "All 114" link,
which the build wired to 1e (kept) because that is where the design's own
anchor points — but the label plainly means all 114 sūras, so the design
intended an index and never drew it.

**Shape of the gap:** an index screen — 114 sūras with their names, revelation
order and progress, opening any aya into 1a. It pairs with finding 2: both are
the same missing idea, that a reader may want an aya the walk did not choose.
Together they make 1a addressable rather than sequential.

**Open question for the walk:** does reading an aya you chose count toward
progress the same as one the walk served you? Decided for finding 2 that it
does, because position is derived and understanding an aya is understanding it
wherever you met it. Same answer should hold here.

### 4. Tapping a word does not speak it, and nothing says long-press will

**Where:** 1a, the word row. `study_screen.dart:466-467`.

**What:** `onTap` opens the root panel, and only when the word has a root.
`onLongPress` speaks the word. A reader taps a word expecting to hear it, gets
a root panel or nothing at all, and never discovers the audio.

**Why it is this way:** the design gives no per-word audio affordance — its 1a
has one play button for the whole set, and underlined words that open roots.
Per-word playback came from the plan's acceptance row ("long-press plays one
word"), so it was added on the only gesture the design had left free. Nothing
in the design signals it because the design never had it.

**Shape of the gap:** a gesture conflict, not a missing feature — and the two
actions are not actually in competition. Tapping a word means "tell me about
this word", and speaking it and opening its root are both answers to that. The
cleanest resolution is that one tap does both: the word sounds and its root
panel swaps. That also fixes the dead case, where a word with no root has no
tap action at all — it can still be spoken.

Whatever gesture wins, discoverability is the real defect: a reader must be
able to tell by looking that a word can be heard. Underlining currently means
"has a root" and carries no audio meaning.

**Constraint:** a word only speaks if its aya is cached. Uncached, the app
shows the transliteration instead and plays nothing, deliberately — it must
never spin. Whatever affordance is drawn has to be honest about that state.

### 5. The reader cannot shape the prayer before entering it

**Where:** set generation (`sets.dart`) and 1b (`prayer_cursor.dart:24`).

**What the reader wants:** to decide in advance how many ayas the prayer will
carry, knowing the portion is recited twice.

**What the app does:** picks the portion itself. A set is a run of consecutive
unread ayas sized by a word-count budget — a tunable constant with no control
on any screen. 1b then counts readings open-endedly: `reading => _position ~/
words + 1` yields a 3rd and a 4th reading with nothing saying a prayer has two.

**The real gap, larger than the request:** the app models READING, not PRAYING.
It knows sets, ayas and words; it does not know rakʿāt, or that the Qur'an
portion after al-Fātiḥa falls in the first two rakʿāt whatever the prayer, or
which of the five prayers this is. "Read twice" is currently an observation the
cursor makes, not a structure the app holds.

**The design assumed more than the build has.** 1a's header reads "Maghrib ·
18:42 · set 412" — a named prayer at its time — and 1b's strip reads "2nd
reading". So the design took a prayer-aware app for granted: which prayer, when
it falls, how many readings it wants. None of that exists. There are no prayer
times, no prayer names, and no rakʿah model anywhere in the code.

**Shape of the gap:**
- A prayer as a first-class thing: which of the five, how many rakʿāt, how many
  readings of the portion.
- The reader choosing the portion — by aya count, or by "as much as I can hold"
  — instead of a constant choosing it for them.
- 1b bounded by that choice: it knows when the prayer's readings are done
  rather than counting upward forever.
- Prayer times, if the header is to mean what the design says. That is a real
  feature with its own dependencies (location, calculation method, madhhab for
  ʿAsr) and should be decided separately rather than smuggled in.

**Note:** the word-count budget was not arbitrary — it exists so that 2:282,
128 words long, cannot stall the walk. Whatever the reader chooses, that guard
still has to hold.

### 6. A two-line gloss breaks the row, because the underline belongs to the wrong thing

**Where:** 1a, the word row. `study_screen.dart:455-476`.

**What:** when a gloss wraps to two lines, that word falls out of alignment
with its neighbours.

**Cause:** the underline is a bottom border on the WHOLE word tile, and the
tile is as tall as its gloss. `Wrap` aligns tops, so the Arabic is correct and
the underline of a two-line word sits lower than the rest. The row of
underlines stops reading as a line.

**The design has the same tension and dodged it the other way.** Its word box
is `align-items:flex-end`, which levels the bottoms — underlines align, and the
ARABIC falls out of line instead. The mockup hides this by hand-breaking its
glosses ("By the<br>passing age", "righteous<br>deeds") so every word is the
same height. Real gloss text is not that tidy.

**Fix:** attach the underline to the Arabic rather than to the tile. Then the
Arabic aligns, the underlines align, and the glosses hang below at whatever
height they need. Neither of the two alignments has to lose.

### 7. The bottom actions are too heavy for what they do

**Where:** 1a, the bottom of the root panel. `study_screen.dart:386-392`.

**What:** two full-width buttons in a permanent bottom bar, "Open
constellation" and "Mark set understood", carrying equal visual weight.

**Why:** taken from the design, which gives them `flex:1` and `flex:1.2` side
by side.

**What is wrong with it:** the two are not peers. "Mark set understood" is the
one action that advances the reader through the Qur'an. "Open constellation"
is an occasional detour into a tablet layout. Giving them near-equal weight
tells the reader they are equally important, and the bar costs permanent
vertical space that the aya — the thing the screen is for — does not get.

**Shape of the fix:** one primary action, and demote the detour to something
lighter within the root panel it belongs to. Worth taking together with finding
2, since "Open constellation" and "Read the aya" are both navigation out of the
root panel and should not each get their own button.

---

## Finding 1 — resolved direction (2026-09-23)

**Lane via Perseus is blocked.** Perseus publishes the TEI under **CC BY-SA
3.0 US**. Creative Commons states verbatim that "no non-CC licenses have been
designated as compatible with BY-SA 3.0" — the one-way route to the GPL family
exists only from 4.0. Independently, Perseus's "offer Perseus any modifications
you make" clause is a further restriction AGPL-3.0 §7 forbids. Two separate bars.

Painful, because the data was measured and it was excellent: **1,582 of 1,642
roots (96.3%), covering 99.2% of occurrences**, have a non-stub article after
the hamza fold. The obstacle is entirely the digitisation, not the book.

**Decided: OCR the public-domain scans ourselves.** Lane died in 1876 and the
lexicon was published 1863–93, so the WORK is public domain; what CC BY-SA 3.0
covers is Perseus's particular transcription of it. A faithful scan of a
public-domain text carries no new copyright (Bridgeman v. Corel in the US;
Art. 14 of the 2019 DSM Directive in the EU), so the archive.org page images are
clean, and anything we OCR from them is ours.

**The simplification that makes this tractable:** we do not need Arabic OCR.
We already hold the root inventory — 1,642 roots, keyed and counted, from the
Qur'anic Arabic Corpus. What Lane adds is **English prose**, and English OCR of
printed 19th-century type is a solved problem. The hard part is *locating* the
right article, not reading it, and Lane is ordered alphabetically by root.

**Open questions for that track**, not for this round:
- Which archive.org scan set, and at what resolution.
- How to locate an article without consulting the encumbered XML — using a
  CC BY-SA work as a finding aid and then OCRing the scan is a grey area best
  avoided outright.
- Lane's articles carry Qur'anic sense-notes and quote exegetes inline. The
  guardrail stands: the poetic register is a claim about the WORD, never about a
  verse. A rule about which parts of an article are in bounds has to exist before
  a single meaning is written.
- Lane is 1863–93 and carries its period's framing on slavery, women and race.
  An editorial policy has to exist before his voice becomes the app's.

---

# Walk two — on the phone (Xiaomi, Android 16)

Build tested: the APK from before Round C landed, so findings 2, 3 and 4 were
not in it. Recorded here anyway where the phone showed something the simulator
did not.

### 8. Audio starts and the reader cannot tell what is playing

**Where:** 1a, on tap or long-press of a word.

**What the reader said:** "the audio launches, with very little feedback — is
it the whole recitation? this specific word?"

**What exists today:** the sounding word gets a highlight (an accent fill at
16% and an accent underline), and there is an audio bar with a play button, a
waveform and the reciter's name. That is all.

**Why it is not enough, and the phone is what exposed it:**
- Playing ONE WORD and playing THE WHOLE SET look identical. Both light a word.
  Nothing distinguishes a single-word probe from a running recitation.
- The audio bar scrolls with the words. On a phone it is frequently off screen,
  so a reader who has scrolled has no indication that anything is playing at
  all, and no way to stop it.
- There is no stop for a long-pressed word. It plays to its end, and the only
  control is elsewhere and possibly not visible.
- A 16% accent fill is a subtle mark on a small bright screen held at arm's
  length. It reads well on a desktop monitor in a dark room, which is where it
  was designed and reviewed.

**Shape of the gap:** audio needs a persistent, visible STATE rather than only a
moving highlight — what is sounding (one word, one aya, the set), where it is,
and a way to stop it from wherever the reader is. That is a small piece of
permanent chrome, and screen 1a's design has no room reserved for it, so it is
a design decision rather than a wiring job.

**Related, and worth deciding together:** finding 7 says the two bottom buttons
are too heavy for what they do. Whatever space they give back is roughly the
space a transport control needs.

### 9. Still no way to choose a sūra or aya — unfixed in the tested build

Finding 3, confirmed on the phone. The fix landed in the tree as 0e9eb57 after
this APK was built; it has not been tested on a device yet.

### 10. The release build had no network at all

**Where:** `app/android/app/src/main/AndroidManifest.xml`.

**What:** Flutter's template grants `android.permission.INTERNET` in the debug
and profile manifests only. `main/` had none, so every release APK shipped
with no network access.

**Why nobody saw it:** the failure is silent by design. `AudioCache.prefetch`
swallows its exceptions so audio can never spin or error mid-prayer — correct
for screen 1b, and it means a total network outage looks exactly like an aya
that has not been downloaded yet. The reported symptom was "a single tap only
shows the transliteration", which is the honest uncached fallback doing its job
over a cause nobody had suspected.

Fixed. Worth noting the shape: a deliberate silent failure hid a real one. The
plan's own rule — never spin, never error — is right, and it cost this.

### 11. The sūra chooser exists and cannot be found

**What the reader said:** "we cruelly lack a sourat chooser".

**What is true:** the index was built and shipped in this very APK. It is
reachable only from inside 1a's settings panel, which is collapsed by default.

**Why:** the design draws no door to it. The navigation agent put it in the
settings panel because "1a's chrome is fixed by its acceptance row", and said
at the time that the choice was defensible but not good. The reader's verdict
settles it: a feature nobody can find is a feature that does not exist.

### 12. The settings panel is three unrelated things in a trenchcoat

**What the reader said:** "the setting menu is terrible UX: we need a proper
setting menu separated from the pray Aya chooser".

**What is in it now:** display mode, reading order, microphone permission,
Arabic size, "Pray this set", "Your passage", "Kept", parked writes, and
"Sources and licences". That is preferences, navigation and actions in one
collapsed drawer, because it was the only place the design left free.

**Shape of the gap:** three different things need three different homes —
preferences that are set and forgotten, navigation to other screens, and the
act of entering a prayer. The last of those is the most wrongly placed: starting
a prayer is the app's central act and it currently lives in a settings drawer.

### 13. Tap and long-press are the wrong way round — the reader's revised call

**Earlier decision, from walk one:** tap speaks the word, long-press opens the
root. Built and shipped.

**Revised, after using it:** single tap opens the ROOT; long-press plays the
audio. The root is the far more frequent intent, and the frequent thing belongs
on the cheaper gesture.

This is a reversal and it is the right kind: the first call was made from a
description, the second from use. Record both so nobody "fixes" it back.

**And the part that stands whichever way round it goes:** there is no feedback
showing which word's root is currently open. The underline ladder does mark it
(`accent` for the selected word, `accent-700` for other rooted words) but on a
phone that distinction is invisible. A reader cannot tell which word the panel
below belongs to.

### 14. From a root's derivatives, the reader cannot reach the aya

**What the reader said:** "aya navigation through word of the root details is
lacking."

Finding 2 fixed the kin rows in 1a's own root panel. Screen 3a — the dial, with
its list of derivatives and their references — still does not open them. Same
gap, different screen, and 3a is where a reader actually studies a root.
