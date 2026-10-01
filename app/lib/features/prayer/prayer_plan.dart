import '../../data/sets.dart';
import '../index/index_screen.dart';
export '../index/sura_picker.dart' show foldLatin, parseRef, searchSuras;

/// The five obligatory prayers, each a preset for how many rakʿahs it has.
///
/// A preset and not a rule: the reader can still change the count, because a
/// prayer shortened while travelling is two rakʿahs of Ẓuhr, and a sunna or a
/// nafl has no preset at all.
enum PrayerPreset {
  fajr(2),
  zuhr(4),
  asr(4),
  maghrib(3),
  isha(4);

  const PrayerPreset(this.rakahs);

  final int rakahs;
}

/// The fewest and most rakʿahs the stepper offers. Twelve covers every prayer
/// a reader would prepare on a phone, ṭarāwīḥ prayed in pairs included.
const minRakahs = 1;
const maxRakahs = 12;

/// What the reader prepared: how many rakʿahs, and what is recited after
/// Al-Fātiḥa in the first two. Al-Fātiḥa is recited in every rakʿah and is
/// not part of the plan, and the rakʿahs after the second are Al-Fātiḥa
/// alone, which is how the obligatory prayers are prayed.
class PrayerPlan {
  const PrayerPlan({
    this.preset,
    required this.rakahs,
    this.first,
    this.second,
    this.sameAsFirst = true,
    this.credited,
  });

  /// Null for a prayer with no preset: a sunna, a nafl, or a count the reader
  /// chose for themselves.
  final PrayerPreset? preset;
  final int rakahs;

  /// The passage after Al-Fātiḥa in the first rakʿah, or null for Al-Fātiḥa
  /// alone.
  final StudySet? first;

  /// The second rakʿah's own passage. Read only when [sameAsFirst] is false.
  final StudySet? second;
  final bool sameAsFirst;

  /// The set this prayer answers for, when it was entered from one: a prayer
  /// that recited it is written to `set_prayers` (ADR 0006). Any other passage
  /// leaves only the device-local history behind.
  final StudySet? credited;

  /// What rakʿah [r], counted from one, recites after Al-Fātiḥa.
  StudySet? passageFor(int r) => switch (r) {
    1 => first,
    2 => sameAsFirst ? first : second,
    _ => null,
  };
}

/// One rakʿah, as the prayer screen draws it and as the voice hears it.
///
/// The two differ by the basmala. A reciter says it before a sūra and the
/// muṣḥaf does not number it, so the screen never shows it — but left out of
/// what the voice listens for, the only place it fits is Al-Fātiḥa's first
/// aya, and a reciter starting their passage would be dragged back to the top
/// of the prayer. Put in, it fits two places equally well: a repeat, which
/// the matcher settles by order (`FollowTuning.repeat` in alignment.dart) —
/// the copy just ahead of the cursor, the one before the passage.
typedef Rakah = ({List<StudyAya> ayas, List<String> heard, int basmalaAt});

/// Al-Fātiḥa and then [passage], for one rakʿah. [fatiha] is the seven ayas
/// with their words, the first of them being the basmala itself.
///
/// `basmalaAt` is where in `heard` the inserted basmala starts, or -1 where
/// there is none: no passage, or At-Tawba, which is recited without one.
Rakah rakahOf(List<StudyAya> fatiha, StudySet? passage) {
  final opening = [
    for (final aya in fatiha)
      for (final w in aya.words) w.text,
  ];
  final said = [
    for (final aya in passage?.ayas ?? const <StudyAya>[])
      for (final w in aya.words) w.text,
  ];
  final basmala =
      fatiha.isEmpty || passage == null || passage.ayas.first.surahId == 9
      ? const <String>[]
      : [for (final w in fatiha.first.words) w.text];
  return (
    ayas: [...fatiha, ...?passage?.ayas],
    heard: [...opening, ...basmala, ...said],
    basmalaAt: basmala.isEmpty ? -1 : opening.length,
  );
}

/// How long [words] take at [wpm] words a minute, rounded the way it is shown:
/// to five seconds under a minute, with five as the least, and to the minute
/// above it. An estimate for choosing a passage, not a timer.
Duration recitingTime(int words, int wpm) {
  final seconds = words * 60 / wpm;
  if (seconds < 60) {
    final five = (seconds / 5).round() * 5;
    return Duration(seconds: five < 5 ? 5 : five);
  }
  return Duration(minutes: (seconds / 60).round());
}

/// What a passage is called where the reader chose it: the sūra's name for a
/// whole sūra, which is how a reader says they recited Al-Ikhlāṣ, and the
/// set's own title — name and ayas — otherwise.
String passageTitle(StudySet set, List<SuraEntry> suras) {
  final first = set.ayas.first;
  final last = set.ayas.last;
  final whole =
      !set.crossesSurah &&
      first.number == 1 &&
      last.number == suras[first.surahId - 1].ayahCount;
  return whole ? first.surahNameEn : set.title;
}
