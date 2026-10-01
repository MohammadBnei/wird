import '../../data/sets.dart';
import '../index/index_screen.dart';
import 'voice_follow.dart';

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
/// of the prayer. Put in, it fits two places equally well, and the matcher
/// refuses both (`followMargin` in alignment.dart): the screen waits a moment
/// instead of jumping.
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
  final basmala = passage == null || passage.ayas.first.surahId == 9
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

/// The aya id a reference like `2:255` names, or null when it is not one or
/// names an aya the sūra does not have. `2.255` is accepted too, because a
/// phone keyboard in numbers mode offers the dot before the colon.
int? parseRef(String query, List<SuraEntry> suras) {
  final m = RegExp(r'^(\d{1,3})\s*[:.]\s*(\d{1,3})$').firstMatch(query.trim());
  if (m == null) return null;
  final sura = int.parse(m[1]!);
  final aya = int.parse(m[2]!);
  if (sura < 1 || sura > suras.length) return null;
  if (aya < 1 || aya > suras[sura - 1].ayahCount) return null;
  return sura * 1000 + aya;
}

/// The sūras [query] could mean: by number, by English name typed with or
/// without the marks a transliteration carries, or by Arabic name typed with
/// or without harakāt. An empty query is every sūra.
List<SuraEntry> searchSuras(List<SuraEntry> suras, String query) {
  final q = query.trim();
  if (q.isEmpty) return suras;
  final number = int.tryParse(q);
  if (number != null) return [for (final s in suras) if (s.id == number) s];
  final latin = foldLatin(q);
  final arabic = recitationKey(q.replaceAll(' ', ''));
  return [
    for (final s in suras)
      if ((latin.isNotEmpty && foldLatin(s.nameEn).contains(latin)) ||
          (arabic.isNotEmpty &&
              recitationKey(s.nameAr.replaceAll(' ', '')).contains(arabic)))
        s,
  ];
}

/// A transliterated name reduced to plain letters, so `Al-Fātiḥa`, `fatiha`
/// and `Al-Fatihah` meet. The corpus spells its names in plain ASCII and the
/// reader may not, so both sides fold.
///
/// ponytail: a table of the marks sūra-name transliterations use, not a
/// Unicode decomposition. Dart has none built in; widen the table if a name
/// turns up that it misses.
String foldLatin(String s) {
  const marks = {
    'ā': 'a', 'á': 'a', 'à': 'a', 'â': 'a', 'ī': 'i', 'í': 'i', 'î': 'i', //
    'ū': 'u', 'ú': 'u', 'û': 'u', 'ḥ': 'h', 'ṣ': 's', 'ḍ': 'd', 'ṭ': 't', //
    'ẓ': 'z', 'é': 'e', 'è': 'e', 'ê': 'e',
  };
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final plain = marks[ch] ?? ch;
    if (RegExp('[a-z0-9]').hasMatch(plain)) out.write(plain);
  }
  // A trailing h is how half the transliterations end a tāʾ marbūṭa and the
  // other half do not, so it never decides a match.
  final folded = out.toString();
  return folded.endsWith('h') ? folded.substring(0, folded.length - 1) : folded;
}
