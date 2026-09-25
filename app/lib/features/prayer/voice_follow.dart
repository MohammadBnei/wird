/// Turning a word into the letters a voice and a muṣḥaf can agree on.
///
/// The matching itself lives in `alignment.dart`. What is left here is the one
/// thing both sides of that comparison have to pass through first.
library;

/// The muṣḥaf and a recogniser do not spell one word the same way. One is
/// fully vowelled Uthmani carrying the Qur'anic annotation marks, the other
/// writes plain Arabic and guesses at a hamza. Both sides are reduced to the
/// letters they agree on, which is what makes the Uthmani and the heard
/// spelling of al-insān the same word.
String recitationKey(String word) {
  final letters = StringBuffer();
  for (final rune in word.runes) {
    final folded = switch (rune) {
      0x0622 || 0x0623 || 0x0625 || 0x0627 || 0x0671 => 0x0627, // آ أ إ ا ٱ
      0x0649 => 0x064A, // ى to ي
      0x0629 => 0x0647, // ة to ه
      // The dagger alif is the long ā the muṣḥaf writes above the line and a
      // recogniser writes on it. Spelling it out costs a letter on the few
      // words modern orthography also leaves it off, such as ar-Raḥmān, and
      // buys an exact match on every word where it does not.
      0x0670 => 0x0627,
      _ => rune,
    };
    // Everything a reciter's voice cannot distinguish for us: the harakāt, the
    // sukūn, the waqf marks, tatwīl.
    if (folded >= 0x0621 && folded <= 0x064A && folded != 0x0640) {
      letters.writeCharCode(folded);
    }
  }
  return letters.toString();
}

/// The set's words in the form [locate] compares against.
List<String> recitationKeys(Iterable<String> words) => [
  for (final word in words) recitationKey(word),
];
