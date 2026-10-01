# 18. A prayer is prepared, then recited one rakʿah at a time

Date: 2026-10-01. Status: accepted. Amends ADR 0006.

## Context

"Pray this set" pushed screen 1b straight onto the set and recorded a `set_prayed` op on the way back. The screen showed the set as one text. That is not how a prayer is prayed. Every rakʿah opens with Al-Fātiḥa, only the first two carry a passage after it, and the number of rakʿahs depends on the prayer. A reader also prays passages that are not the walk's set: a sūra they know, Al-Fātiḥa alone, a different passage in the second rakʿah.

Voice-follow was built for one text. It listened to a set, and the reader re-started it by tapping. Three things broke once the prayer was split into rakʿahs:

- Loading the model takes up to 20 seconds ([prayer_voice.dart:65](../../app/lib/features/prayer/prayer_voice.dart#L65-L69)). A new recogniser per rakʿah would miss the start of each one.
- Between two rakʿahs the reader says "al-ḥamdu lillāh" and "rabbanā wa laka l-ḥamd". A short window of that matches Al-Fātiḥa 1:2.
- A reciter says the basmala before the passage, and the muṣḥaf does not show it there. The only place it fits is Al-Fātiḥa 1:1. Measured, "بسم الله" alone scored 0.83 on word 1, so the screen jumped back to the top of the prayer.

The design also asks for a steady pace for readers who do not use the voice, and for voice and pace together.

## Decision

A prayer is prepared on its own screen, then recited one rakʿah at a time.

- **Preparation.** `PrepareScreen` sets the preset (Fajr 2, Ẓuhr 4, ʿAṣr 4, Maghrib 3, ʿIshāʾ 4, or none), the rakʿahs (1 to 12), the passage after Al-Fātiḥa in the first two rakʿahs, voice and pace (15 to 90 words a minute), gloss, faded neighbours and Arabic size ([prepare_screen.dart:19](../../app/lib/features/prayer/prepare_screen.dart#L19-L41)). `Routes.prayer` is gone. "Pray this set" opens `Routes.prepare` on the set, and a home door opens it with none ([app.dart:353](../../app/lib/app.dart#L353-L357)). "Silence notifications" is a reminder only.
- **Recording.** 1b still writes nothing. It reports the rakʿah reached through `PrayerOutcome`. On the way back, Prepare writes `prayer_prefs` and one `prayer_history` row per recited passage, both device-local. It calls `recordSetPrayed` for the credited set only if a reached rakʿah recited it. The credited set is the one Prepare was opened on, else `nextSet` ([prepare_screen.dart:218](../../app/lib/features/prayer/prepare_screen.dart#L218-L233)).
- **One voice per prayer.** The microphone and model open once. `follow` points them at each new rakʿah and drops any answer still in flight by a generation counter ([prayer_voice.dart:547](../../app/lib/features/prayer/prayer_voice.dart#L547-L557)).
- **Al-Fātiḥa opens a rakʿah.** Between rakʿahs only a sure, full window landing in Al-Fātiḥa's first two ayas begins the next one ([prayer_voice.dart:561](../../app/lib/features/prayer/prayer_voice.dart#L561-L567)). A tap also begins it.
- **The unseen basmala.** What the voice hears carries a basmala before each passage, except At-Tawba. The screen never shows it ([prayer_plan.dart:83](../../app/lib/features/prayer/prayer_plan.dart#L83-L101)). A basmala then fits two places and the margin refuses both.
- **Pace behind the voice.** The voice leads. After 3 seconds with no sure match, the pace steps the words from the last sure word. Any sure match pauses it, the same word again included. The pace's own steps never count as a match ([prayer_pace.dart:79](../../app/lib/features/prayer/prayer_pace.dart#L79-L92)).
- **Taps stay.** The large zone goes to the next aya and the narrow one back an aya, in every mode. With neither voice nor pace, the large zone steps one word ([prayer_screen.dart:374](../../app/lib/features/prayer/prayer_screen.dart#L374-L401)). The 1-second dwell stays. The echo line of matched words is removed.

## Alternatives

- **Credit the set and keep no history.** Loses "recently recited" in the passage chooser.
- **A synced log of every prayer.** A one-way server schema for a feature that is still settling.
- **"Pray this set" skips Prepare.** Two ways into a prayer, with two sets of defaults.
- **Voice and pace as exclusive modes.** Diverges from the design, and a reader who loses the voice is left with nothing moving.
- **Taps as drawn in the mockup.** Word steps only with both off, nothing otherwise. No way to correct a pace that runs ahead.
- **Start the next rakʿah on a timer**, as the mockup does. Rakʿah length varies with the reader and the passage.
- **Start it on the first sure match.** Bowing praise matches 1:2.
- **A real do-not-disturb toggle.** Android needs a notification-policy permission flow, and iOS has no API.

## Consequences

- ADR 0006 is amended. A set is still answered for, but only when a reached rakʿah recited it. A prayer can recite passages that are not sets, and those leave only device-local history.
- The prayer count can now be short in one more way: a prayer left before the rakʿah that held the set is not counted. It still never over-counts.
- `prayer_prefs` and `prayer_history` never leave the phone. A second device starts with defaults and no recent passages.
- `PrayerVoice` must keep `follow`, the generation check and the opening gate together. A change to `openingWords` or `heardTailLetters` changes what can begin a rakʿah.
- Every rakʿah now contains Al-Fātiḥa, so the repeated-phrase refusal of finding 9 in the voice-follow walk is met in every prayer.
- `prayer_history` grows by one row per recited passage and is never pruned (a marked ceiling in `notePassageRecited`).

## Reversibility

Moderate. The history and prefs tables are local and can be dropped. The route and the screen are app-only. The credit rule is the one-way part: rows already written stay. Signals to revisit: readers asking for prayers on another device (sync the history), a basmala still pulling the screen back (revisit the insertion), or praise still beginning a rakʿah in field walks (tighten the opening gate).
