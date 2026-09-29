/// Turning a word into the letters a voice and a muṣḥaf can agree on.
///
/// The matching itself lives in `alignment.dart`. What is left here is the one
/// thing both sides of that comparison have to pass through first.
library;

/// The muṣḥaf and a recogniser do not spell one word the same way. One is
/// fully vowelled Uthmani carrying the Qur'anic annotation marks, the other
/// writes the sounds it heard. Both sides are reduced to the letters they
/// agree on, which is what makes the Uthmani and the heard spelling of
/// al-insān the same word.
///
/// The recogniser writes Qur'anic phonemes rather than words: gemination is
/// the letter written twice, a madd is the vowel held for as many marks as it
/// is held for, and the tajwīd of a sound rides above it. None of that is a
/// different word — ٱلرَّحْمَٰنِ recited is `رَحمَاانِ` and written is `الرحمان` —
/// so a run of one letter folds to that letter and the marks fall away with
/// the harakāt.
String recitationKey(String word) {
  final letters = StringBuffer();
  int? last;
  for (final rune in word.runes) {
    final folded = switch (rune) {
      0x0622 || 0x0623 || 0x0625 || 0x0627 => 0x0627, // آ أ إ ا
      // The waṣl alif, dropped. The muṣḥaf writes it and connected recitation
      // skips it, which is exactly what the sign over it says: ٱلرَّحْمَـٰنِ comes
      // back as رَحمَاانِ. It costs the alif of a word that opens an utterance —
      // ٱقْرَأْ is said iq'ra — and the corpus's own transliteration knows which
      // is which, word by word, `al-yawma` against `l-yawma`. Wiring that in
      // was measured and is worse: the same transliteration romanises ٱلَّذِى as
      // `alladhī` wherever it stands, including the mid-aya رَببِكَللَذِۦۦ where
      // the reciter runs it on, and Ḥuṣarī's in-step windows fell from 116 of
      // 129 to 109. Dropping it always is both shorter and better.
      0x0671 => 0x0640, // ٱ, dropped below with the tatwīl
      // A bare hamza is how the recogniser writes the glottal stop the muṣḥaf
      // writes as a seated one: ٱلْحَمْدُ comes back as ءَلحَمدُ. Folding it to the
      // same letter costs nothing on the few words written with a bare hamza,
      // because both sides fold.
      0x0621 => 0x0627,
      0x0672 => 0x0627, // ٲ, the phoneme alphabet's own alif
      0x0649 => 0x064A, // ى to ي
      0x06E6 => 0x064A, // ۦ, a madd held on a yāʾ
      0x06E5 => 0x0648, // ۥ, a madd held on a wāw
      // The two nasalisations, which the recogniser writes as marks of their
      // own and holds for as long as they are held: ikhfāʾ on a nūn, iqlāb on
      // a mīm. Both are a letter the muṣḥaf writes.
      0x06BA => 0x0646, // ں to ن
      0x06BE => 0x0645, // ۾ to م
      0x0629 => 0x0647, // ة to ه
      // The dagger alif is the long ā the muṣḥaf writes above the line and a
      // recogniser writes on it. Spelling it out costs a letter on the few
      // words modern orthography also leaves it off, such as ar-Raḥmān, and
      // buys an exact match on every word where it does not.
      0x0670 => 0x0627,
      _ => rune,
    };
    // Everything that is not a letter: the harakāt, the sukūn, the waqf marks,
    // tatwīl, and the tajwīd the recogniser rides above a letter — the qalqala
    // on ٱقْرَأْ is written ءِقڇرَء and is the ق echoing, not a sound of its own.
    if (folded < 0x0621 || folded > 0x064A || folded == 0x0640) continue;
    if (folded != last) letters.writeCharCode(folded);
    last = folded;
  }
  return letters.toString();
}

/// The set's words in the form [locate] compares against.
List<String> recitationKeys(Iterable<String> words) => [
  for (final word in words) recitationKey(word),
];
