# Sets and reader

> How the app picks the next set of ayas on the phone, names it, and shows it as a passage on the reader screen before a prayer. Level L2 · Parent [App](../app.md) · Children none

## Black box

This part of the app answers one question with no network: what should the reader read next? It proposes a **set**, a few ayas that fit in the head for one prayer. The reader screen (screen 1a) shows a whole sūra, opened where the reader last stood or at any aya they ask for. From there the reader marks ayas understood one by one, walks the sūra a word at a time, or prays the ayas around them. Both writes land in the **outbox** and reach the server later.

| In | Out | Depends on |
|---|---|---|
| The ayas already understood, the reading order, how wide the reader likes a set, an aya chosen from the index or a root | The next set, a passage to read, a set id that every device agrees on, "understood" and "prayed" writes | The bundled **corpus**, the **outbox**, the app's recitation player, the prayer screen |

```mermaid
sequenceDiagram
  actor R as Reader
  participant S as Sets and reader
  participant C as Corpus on the phone
  participant O as Outbox
  participant P as Prayer screen 1b
  R->>S: open the set
  S->>C: which ayas are not understood yet?
  C-->>S: next few ayas, with their words
  S-->>R: passage on screen 1a
  R->>S: tap an aya's number
  S->>O: aya understood
  R->>S: stay on a word
  S->>O: position moved
  R->>S: Pray this set
  S->>P: the set, already read
  P-->>S: reader comes back
  S->>O: set prayed, with its derived id
```

Nothing here waits on the network. The server only learns about a set when the outbox flushes. It can check the set's id on its own, because the id is computed from the set and nothing else.

```mermaid
flowchart LR
  walk(["The walk<br/>next set not yet understood"]) --> reader["Reader screen 1a"]
  index(["Sūra index"]) -->|"an aya"| reader
  root(["A root or its family"]) -->|"an aya"| reader
  reader -->|"Pray this set"| prayer["Prayer 1b"]
  reader -->|"aya understood, position"| outbox[("Outbox")]
  prayer -->|"on the way back"| outbox
```

## White box

```mermaid
flowchart TB
  subgraph data["app/lib/data/sets.dart"]
    nextSet["nextSet<br/>the walk"]
    ayaSet["ayaSet<br/>a place in a sūra"]
    width["_setWidth<br/>5 ayas, 25 words"]
    span[("set_span<br/>width the reader chose")]
    id["setIdFor<br/>uuidv5 of order:start:end"]
    studySet["StudySet<br/>ayas = acted on<br/>reading = drawn"]
  end
  subgraph screen["Screen 1a, study_screen.dart"]
    load["_load"]
    list["lazy CustomScrollView"]
    mark["_markUnderstood"]
  end
  nextSet --> width
  span --> width
  nextSet --> studySet
  ayaSet --> studySet
  studySet --> id
  load --> nextSet
  load --> ayaSet
  load --> list
  mark --> db1["markSetUnderstood<br/>ayah_understood + outbox"]
  pray["prayTheSet in app.dart"] --> db2["recordSetPrayed<br/>sets + set_prayers + outbox"]
  studySet --> pray
```

The screen has two modes that are really one: on the walk, or visiting. Only the load differs.

```mermaid
stateDiagram-v2
  [*] --> OnTheWalk: open 1a with no target
  OnTheWalk --> Visiting: index, kin, root family, footer step
  Visiting --> Visiting: another aya or step
  Visiting --> OnTheWalk: Back to the walk
  OnTheWalk --> OnTheWalk: mark understood, then Next set
  Visiting --> OnTheWalk: mark understood, then Next set
  OnTheWalk --> Prayer: Pray this set
  Visiting --> Prayer: Pray this set
  Prayer --> OnTheWalk: back, prayer recorded
  Prayer --> Visiting: back, prayer recorded
```

### 1. The walk finds the next set

There is no stored position. [`nextSet`](../../../app/lib/data/sets.dart#L227-L271) looks for the first aya not yet understood in the chosen order, and reads up to 20 ayas from there. The order is one SQL expression per choice, so switching between revelation order (`nuzul`, the default) and written order (`mushaf`) never corrupts progress ([sets.dart:61](../../../app/lib/data/sets.dart#L61-L64)).

A set is a run of consecutive ayas that are not understood. It stops before the next understood aya, unless the reader widened the set on purpose:

```dart
  final reachable = span == null
      ? rows.takeWhile((r) => (r['understood']! as int) == 0).toList()
      : rows;
  final taken = reachable
      .take(
        _setWidth([
          for (final r in reachable) r['word_count']! as int,
        ], span: span),
      )
      .toList();

  return _setFrom(db, order, taken);
```

[sets.dart:259](../../../app/lib/data/sets.dart#L259-L270). When nothing is left, it returns null and the screen shows a "nothing left" message ([study_screen.dart:564](../../../app/lib/features/study/study_screen.dart#L564-L573)).

### 2. How wide a set is

The proposal is at most 5 ayas and 25 words ([sets.dart:13](../../../app/lib/data/sets.dart#L13-L20)). The first aya always goes in, whatever it costs, or 2:282 (128 words) would stall the walk forever. If the reader chose a width in Settings, that width wins, up to 20 ayas.

```dart
int _setWidth(List<int> wordCounts, {int? span}) {
  if (span != null) {
    return span.clamp(1, max(1, min(setMaxDragAyas, wordCounts.length)));
  }
  var taken = 0;
  var words = 0;
  for (final count in wordCounts) {
    if (taken == setMaxAyas) break;
    if (taken > 0 && words + count > setWordBudget) break;
    words += count;
    taken++;
  }
  return taken;
}
```

[sets.dart:460](../../../app/lib/data/sets.dart#L460-L473). The chosen width is stored per starting aya in the local `set_span` table ([sets.dart:481](../../../app/lib/data/sets.dart#L481-L498)). It is a width, never a position, and it never leaves the phone. The Settings stepper writes it ([settings_screen.dart:71](../../../app/lib/features/settings/settings_screen.dart#L71-L78)).

### 3. A set's id is derived, not minted

Every device must name the same set the same way, with no server round trip. So the id is a UUID v5 over the reading order and the first and last aya ids. The namespace is itself derived, so no one copies a magic string by hand.

```dart
final _setNamespace = _uuidV5(
  '6ba7b811-9dad-11d1-80b4-00c04fd430c8', // RFC 9562 NameSpace_URL
  'https://wird.bnei.dev/set',
);

/// A set's identity, which is a pure function of the range it holds and the
/// order it was read in. Nothing is minted and nothing is counted, so a
/// reinstall and a second device arrive at the same id for the same range
/// without having to agree on one — and because it says nothing about where
/// the reader is, the reading order stays switchable.
String setIdFor(ReadingOrder order, int startAyahId, int endAyahId) =>
    _uuidV5(_setNamespace, '${order.name}:$startAyahId:$endAyahId');
```

[sets.dart:28](../../../app/lib/data/sets.dart#L28-L39). A set asks for its id through [`StudySet.id`](../../../app/lib/data/sets.dart#L191). The server recomputes the same id and refuses a mismatch ([sync.go:378](../../../server/internal/store/sync.go#L380)). Shared test vectors keep both sides honest: see [ADR 0002](../../adr/0002-set-identity.md#the-vectors).

### 4. A passage: what is read versus what is acted on

A `StudySet` holds two lists ([sets.dart:146](../../../app/lib/data/sets.dart#L146-L163)):

- `ayas` is what the reader acts on. It is marked, prayed, named in the header, pinned on disk, and it gives the set its id.
- `reading` is what the screen draws. On the walk it is the same list. Off the walk it is the whole sūra.

[`ayaSet`](../../../app/lib/data/sets.dart#L290-L318) builds the off-walk case. It reads every aya of the sūra, but only the acted ayas arrive with their words:

```dart
  final at = rows.indexWhere((r) => r['id'] == ayahId);
  if (at < 0) return null;
  final acted = rows.sublist(at, min(at + max(1, ayas), rows.length));
  final words = await wordsFor(db, [for (final r in acted) r['id']! as int]);
  return StudySet(
    order: order,
    _ayasOf(acted, words),
    reading: _ayasOf(rows, words),
  );
```

[sets.dart:309](../../../app/lib/data/sets.dart#L309-L317). Scrolling through 286 ayas of Al-Baqarah writes nothing, so the walk does not move.

### 5. Screen 1a opens a sūra where the reader stood

Since [ADR 0014](../../adr/0014-the-reading-screen-reads-a-whole-sura-a-word-at-a-time.md) the reading screen holds one whole sūra. [`_load`](../../../app/lib/features/study/study_screen.dart#L123-L161) picks the word it opens on:

```dart
    var at = word ?? (target == null ? null : target * 1000 + 1);
    if (at == null) {
      final positions = await readingPositions(widget.db);
      if (positions.isNotEmpty) {
        at = positions.first.wordId;
      } else {
```

[study_screen.dart:123](../../../app/lib/features/study/study_screen.dart#L123-L161).

- A word, from home's "Continue reading": that word.
- An aya, from the index, a root or the walk's set on home: its first word.
- Nothing: where the reader last stood in any sūra, else the walk's next aya, else 1:1.

The sūra comes from [`ayaSet`](../../../app/lib/data/sets.dart#L295-L337), whose `reading` is every aya of it. The screen keeps that set while the reader walks, so the list never rebuilds under them.

### 6. The sūra list is lazy both ways

A sūra can be 286 ayas and 6116 words. The top of the screen is a `CustomScrollView` hung from the aya the reader opened on. Slivers before the anchor grow upward, slivers after it grow downward ([study_screen.dart:516](../../../app/lib/features/study/study_screen.dart#L516-L549)). An aya with no words yet draws a placeholder of about the right height and asks for the words around it: 4 ayas back, 12 ahead, in one query ([study_screen.dart:706](../../../app/lib/features/study/study_screen.dart#L706-L727), [sets.dart:394](../../../app/lib/data/sets.dart#L394-L421)).

Each word arrives with its English gloss and, where The Last Dialogue's pages carry it, its French one ([ADR 0012](../../adr/0012-french-word-glosses-from-the-last-dialogue.md)). Each aya's translation, Pickthall's English or Rashid Maash's French, sits under it unless the reader turns it off in Settings ([ADR 0017](../../adr/0017-ayas-are-translated-into-english-from-pickthall.md)).

### 7. The root sheet walks the sūra a word at a time

A tap on any word, particles included, opens it in the sheet under the list. [`_open`](../../../app/lib/features/study/study_screen.dart#L173-L197) reads everything the sheet shows before it draws any of it:

- the root;
- its lemmas;
- how often the root is read in this sūra;
- up to 20 other ayas it is read in;
- the word's parsing.

That way the sheet never shows one word's root beside another word's counts.

```mermaid
flowchart LR
  tap(["tap a word"]) --> open["_open"]
  swipe(["drag the sheet<br/>past 60px"]) --> step["_step"]
  arrows(["hint row ends<br/>or arrow keys"]) --> step
  step --> walk["stepFrom<br/>by aya, not by index"]
  walk -->|"aya not read yet"| read["_readWordsAround"]
  read --> walk
  walk --> open
  open --> settle["after 2 s:<br/>movePosition"]
  open --> carry["_carry<br/>recitation around the word"]
```

A drag to the right moves to the next word, because Arabic runs leftward. The sheet slides: the finger carries the content, and past 60px it keeps going off that side while the next word is read, then the new word comes in from the other side ([word_swipe.dart:119](../../../app/lib/features/study/word_swipe.dart#L119-L126)). The two ends of the hint row and the arrow keys slide the same way ([word_swipe.dart:61](../../../app/lib/features/study/word_swipe.dart#L61)); any other change of word, such as a tap in the sūra, fades instead. A drag that starts within 24px of the edge is left to the drawer and the back gesture.

The sheet reads in one order. The first row holds the root, the word as this aya writes it, and what it means here. Then come the root's senses, with the reader's thumbs on their heading. Then comes the word's form, meaning its parsing, with the corpus's attribution. The open word glows in the accent inside its aya, in the sūra and in the open aya above the sheet; on the sheet's own row it is plain. Prayer keeps a near-white glow of its own, so the two never read alike ([glow.dart](../../../app/lib/theme/glow.dart#L13-L24)).

A step is found by aya ([`stepFrom`](../../../app/lib/features/study/reading_walk.dart#L17-L37)): past the end of an aya it goes to the next aya, read or not, and the screen reads that aya's chunk before stepping again ([study_screen.dart:269](../../../app/lib/features/study/study_screen.dart#L269-L285)). Counting along a flat list of the words read so far landed a step from 2:255 back near 2:1.

Once the reader has stayed on a word for two seconds, and again when they leave, it is written as their position in that sūra and queued for their other devices ([ADR 0015](../../adr/0015-the-reading-position-is-kept-per-sura-and-synced.md), [`movePosition`](../../../app/lib/data/db.dart#L438-L457)).

A tap on the sheet's top bar, or on its "Counts, forms, other ayas" row, shrinks the sūra to the open word's aya, whole and with its translation, and brings up the counts, the ring of the root's lemmas and the other ayas; scrolling the sheet never does. Each other aya is shown as a line around the root's word in it, lit, so the word it is listed for is never cut off. An other aya opens in place of the sūra, with a way back to the word the reader was on and a way to read that aya's sūra from there.

The root letters open the root's own screen. A screen that names an aya answers by popping its id back down, and the reader reloads in place rather than stacking a second reader ([study_screen.dart:319](../../../app/lib/features/study/study_screen.dart#L319-L323)):

- the sūra index, reached from the sūra's name in the bar;
- a root, its spine and the constellation, which call one helper ([family.dart:38](../../../app/lib/features/root/family.dart#L38-L39));
- Progress (1d), whose "All 114" opens the index and passes its answer on ([progress_screen.dart:49](../../../app/lib/features/progress/progress_screen.dart#L49-L53)).

The drawer and home catch an aya too, and push the reader with it ([wird_shell.dart:229](../../../app/lib/shell/wird_shell.dart#L229-L242)).

### 8. Marking an aya understood

The circle that closes each aya marks it understood when tapped ([study_screen.dart:314](../../../app/lib/features/study/study_screen.dart#L314-L318)). The write goes through [`markSetUnderstood`](../../../app/lib/data/db.dart#L299-L327) with a fresh op id per tap. It inserts into `ayah_understood` and queues one `ayah_understood` op in the same transaction. An aya already understood answers no tap: no op takes the mark back.

Scrolling or walking past an aya marks nothing. Understood is what the reader says, and the position is where they are; neither is read from the other.

### 9. Praying a set

The walk still proposes sets, and home still offers "Pray this set". The reading screen's Pray action prays the ayas around the open word, the reading width wide: the same set the recitation carries ([study_screen.dart:228](../../../app/lib/features/study/study_screen.dart#L228-L265)). Both call one function:

```dart
Future<void> prayTheSet(BuildContext context, StudySet set) async {
  final db = Wird.of(context).db;
  final navigator = Navigator.of(context);
  await Wird.of(context).recitation.stop();
  await navigator.pushNamed(Routes.prayer, arguments: set);
  await recordSetPrayed(db, set);
}
```

[app.dart:312](../../../app/lib/app.dart#L328-L334). The prayer screen writes nothing: it runs inside the prayer, where no moment is safe for a write ([prayer_screen.dart:16](../../../app/lib/features/prayer/prayer_screen.dart#L17-L32)). The prayer is recorded when the reader comes back, however they leave. [`recordSetPrayed`](../../../app/lib/data/db.dart#L340) inserts the set (ignored if it exists), the prayer, and one `set_prayed` op that carries the range and the derived id.

A prayer the reader never returns from is not counted. The count may be short; it is never invented.

### 10. What stays on disk

[`pathsToKeep`](../../../app/lib/data/audio.dart#L107-L127) pins the recitation files the reader will need. The reading screen asks for the ayas around the open word only, and asks again when the reader walks out of them. The walk's next set has nothing to do with where the reader is:

```dart
  final ahead = onTheWalk
      ? await nextSet(db, order, alsoUnderstood: currentIds.toSet())
      : null;
```

[audio.dart:118](../../../app/lib/data/audio.dart#L118-L120).

### 11. What progress counts

Screen 1d replays the walk to count finished sets ([sets.dart:498](../../../app/lib/data/sets.dart#L498-L533)), instead of counting rows in `sets`. A set prayed twice and never marked is not a finished set. The prayer tile counts every recorded prayer, on the walk or not, and is labelled "prayers recorded" for that reason ([passage.dart:160](../../../app/lib/features/progress/passage.dart#L160-L166), [progress_screen.dart:156](../../../app/lib/features/progress/progress_screen.dart#L156-L157)).

## Why it is this way

- [ADR 0002](../../adr/0002-set-identity.md) — a set's id is a UUID v5 of its range and order, and one `set_prayed` op records the set and the prayer together.
- [ADR 0003](../../adr/0003-addressable-reader.md) — the reader screen can open any aya, changes in place, and never stacks a second reader.
- [ADR 0006](../../adr/0006-a-passage-is-read-a-set-is-answered-for.md) — a passage is read, a set is answered for: `reading` versus `ayas`, and the lazy list.
- [ADR 0001](../../adr/0001-stack.md) — the corpus lives on the phone and the app generates its own sets.

## Go deeper

- [Voice-follow](voice-follow.md) — what the prayer screen does with the set while the reader recites.
- [Sync](sync.md) — how the outbox carries "understood" and "prayed" to the server.
- [Senses in the app](senses.md) — what the root panel under the passage shows.
- [Sync endpoints](../api/sync-endpoints.md) — where the server checks the derived set id.
- Tour: [A prayer, from tap to Postgres](../../tours/prayer-to-postgres.md).
