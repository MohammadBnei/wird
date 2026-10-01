package main

import (
	"fmt"
	"strings"
)

// quranBuckwalter is the full extended Buckwalter the Quranic Arabic Corpus
// publishes its forms and lemmas in: letters with their hamza seats, vowels,
// shadda, sukun, tanwin, and the Uthmani marks (dagger alif, wasla, small high
// letters) that the 28-letter root table has no use for. Unlike
// buckwalterArabic it folds nothing — a lemma is shown as written, and إ is
// not أ there.
//
// Checked against the corpus: the forms of every segment, decoded with this
// table and joined, give the word's own Arabic for 66,667 of 77,429 words with
// tatweel set aside. The rest differ only in the pause marks and small letters
// the Quran Foundation text carries and the annotation does not.
var quranBuckwalter = map[rune]rune{
	'\'': 'ء', '|': 'آ', '>': 'أ', '&': 'ؤ', '<': 'إ', '}': 'ئ', 'A': 'ا',
	'b': 'ب', 'p': 'ة', 't': 'ت', 'v': 'ث', 'j': 'ج', 'H': 'ح', 'x': 'خ',
	'd': 'د', '*': 'ذ', 'r': 'ر', 'z': 'ز', 's': 'س', '$': 'ش', 'S': 'ص',
	'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع', 'g': 'غ', '_': 'ـ', 'f': 'ف',
	'q': 'ق', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'h': 'ه', 'w': 'و',
	'Y': 'ى', 'y': 'ي',
	'F': 'ً', 'N': 'ٌ', 'K': 'ٍ', 'a': 'َ', 'u': 'ُ',
	'i': 'ِ', '~': 'ّ', 'o': 'ْ', '^': 'ٓ', '#': 'ٔ',
	'`': 'ٰ', '{': 'ٱ',
	':': 'ۜ', '@': '۟', '"': '۠', '[': 'ۢ', ';': 'ۣ',
	',': 'ۥ', '.': 'ۦ', '!': 'ۨ', '-': '۪', '+': '۫',
	'%': '۬', ']': 'ۭ',
}

// lemmaArabic shows a lemma key as Arabic. The corpus tells apart two lemmas
// spelled alike with a trailing digit (baEol, baEol2); the digit is part of
// the key and never of what the reader sees. A letter outside the table is an
// error rather than a gap: a lemma that loses a letter silently is a word the
// reader cannot recognise.
func lemmaArabic(key string) (string, error) {
	var b strings.Builder
	for _, r := range strings.TrimRight(key, "0123456789") {
		a, ok := quranBuckwalter[r]
		if !ok {
			return "", fmt.Errorf("lemma %q has %q, which the Buckwalter table does not decode", key, r)
		}
		b.WriteRune(a)
	}
	return b.String(), nil
}
