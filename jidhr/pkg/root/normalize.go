package root

import (
	"strings"
	"unicode"
)

// normalize reduces a written Arabic word to the spelling the corpus is keyed by:
// no diacritics, no tatweel, one alef, one ya, one ha. Its contract is
// jidhr/testdata/normalize.json, which the Dart normaliser on the device reads
// too. Unshared, the two drift, recognised speech stops matching the Uthmani text,
// and the in-prayer cursor silently never advances. That file carries the removal
// and folding tables expanded to explicit code points, and the tests below prove
// this function is exactly those tables — so the Dart author implements the file
// and needs nothing from here.
//
// Normalisation is orthographic only. It never removes the definite article and
// never peels a prefix: those are the stripping rung's work, and a normaliser that
// did them would fold الفتح into فتح and hand back the wrong root as a fact.
//
// The error is always nil — every string has a normal form. It is in the signature
// because the ladder calls every rung the same way.
func normalize(word string) (string, error) {
	var b strings.Builder
	b.Grow(len(word))
	for _, r := range word {
		if dropped(r) {
			continue
		}
		b.WriteRune(folded(r))
	}
	return b.String(), nil
}

// dropped reports whether a rune carries no spelling: the Arabic combining marks,
// tatweel, the Uthmani small waw and small ya, and the invisible formatting
// characters that ride along with a verse copied out of a mushaf.
func dropped(r rune) bool {
	switch r {
	case 0x0640, // tatweel, typographic stretching with no sound
		0x06E5, 0x06E6: // small waw and small ya: a lengthened pronoun vowel, not a letter
		return true
	}
	// The harakat are script Inherited rather than Arabic, so unicode.Is(unicode.Arabic, …)
	// leaves every one of them standing. The block test is the one that works.
	return unicode.Is(unicode.Cf, r) || (unicode.Is(unicode.Mn, r) && inArabicBlock(r))
}

// inArabicBlock names the scope of the mark rule: a combining mark is dropped only
// inside these blocks, so a Latin acute or a Hebrew point survives. Arabic Extended-B
// is deliberately in — it carries Qur'anic annotation marks, and leaving it out was
// the exact split the Dart normaliser would have landed on. The blocks are listed in
// testdata/normalize.json under scope, and the ranges they expand to are listed there
// too, so the Dart side needs no Unicode tables at all.
func inArabicBlock(r rune) bool {
	switch {
	case r >= 0x0600 && r <= 0x06FF, // Arabic
		r >= 0x0750 && r <= 0x077F,   // Arabic Supplement
		r >= 0x0870 && r <= 0x089F,   // Arabic Extended-B
		r >= 0x08A0 && r <= 0x08FF,   // Arabic Extended-A
		r >= 0x10EC0 && r <= 0x10EFF: // Arabic Extended-C
		return true
	}
	return false
}

// folded maps the spellings of one letter onto the single spelling the index uses.
// Only seated hamzas fold onto their carriers; a standalone hamza is a letter of
// its own, and دعا is not دعاء.
func folded(r rune) rune {
	switch r {
	case 0x0622, 0x0623, 0x0625, 0x0671: // alef with madda, hamza above, hamza below, wasla
		return 0x0627 // alef
	case 0x0624: // hamza on a waw seat
		return 0x0648 // waw
	case 0x0626: // hamza on a ya seat
		return 0x064A // ya
	case 0x0629: // ta marbuta
		return 0x0647 // ha
	case 0x0649: // alef maqsura
		return 0x064A // ya
	}
	switch {
	case r >= 0x0660 && r <= 0x0669: // Arabic-Indic digits
		return '0' + (r - 0x0660)
	case r >= 0x06F0 && r <= 0x06F9: // the extended set Persian and Urdu keyboards produce
		return '0' + (r - 0x06F0)
	}
	return r
}

// ponytail: two Uthmani rasm conventions are knowingly left unreduced, because
// each needs corpus evidence we will not have until the ingest of phase 3, and a
// wrong fold states a false root rather than missing one. ءامنوا does not reach
// آمنوا, and the waw-with-dagger-alef spellings صلوة، زكوة، حيوة do not reach
// صلاة، زكاة، حياة. Both are closed lists: when phase 11 measures how often
// recognised speech misses because of them, fix them by indexing the modern
// spelling alongside the Uthmani one at ETL time, not by widening this function.
