package root

import (
	"slices"
	"strings"
	"unicode"
)

// Templates are written the way Arabic grammarians write them: over the model root
// ف-ع-ل. In every shape below, ف stands for the first radical, ع for the second and
// ل for the third, and any other letter must appear in the stem exactly as it
// stands here. The shapes are in normalised orthography — no diacritics, ta marbuta
// already written as ha — because that is the spelling that reaches this rung.
//
// Forms I, II and IX are deliberately absent. Once the vowels are gone they are
// spelled exactly like the bare root, so a template for them would fit every
// three-letter word in Arabic and hand the input back as a discovery.
// ponytail: twelve shapes matched letter by letter. The upgrade path is a real
// morphological analyser over a vowelled corpus, which would narrow the candidate
// set this rung hands the store rather than replace the store's verdict.
var baseTemplates = []string{
	"فاعل",    // form III, and the active participle faa3il
	"افعل",    // forms IV and IX
	"تفعل",    // form V
	"تفاعل",   // form VI
	"انفعل",   // form VII
	"افتعل",   // form VIII
	"استفعل",  // form X
	"مفعول",   // maf3uul, the passive participle
	"فعال",    // fa33aal
	"مفعل",    // maf3al
	"استفعال", // istif3aal
	"مفاعله",  // mufaa3ala, its ta marbuta normalised to ha
}

// template is one shape, plus what a doubled root does to the spelling of it.
type template struct {
	shape string

	// doubled marks the spelling a root takes when its last two radicals are the
	// same letter and are written once: است + ر-د-د is استرد. The third radical is
	// still readable, because it is the second one again.
	doubled bool
}

var templates = expandTemplates(baseTemplates)

func expandTemplates(shapes []string) []template {
	var out []template
	add := func(t template) {
		// A three-letter shape is the root restated, for the same reason forms I, II
		// and IX are absent: it fits every three-letter word in the language.
		if len([]rune(t.shape)) > 3 {
			out = append(out, t)
		}
	}
	for _, s := range shapes {
		add(template{shape: s})
		if strings.Contains(s, "عل") {
			add(template{shape: strings.Replace(s, "عل", "ع", 1), doubled: true})
		}
	}
	return out
}

// weakFinals are the letters a defective root writes as its third radical. A
// spelling that may be hiding one of them yields a reading for each, because
// nothing in the letters says which.
var weakFinals = []rune{'و', 'ي'}

// radicalReadings lists the radicals a slot may hold, given the letter the
// normaliser left standing there. The normaliser is keyed for lookup, not for
// spelling: it folds ة onto ه, the hamza seats ؤ and ئ onto و and ي, and ى onto ي
// (jidhr/testdata/normalize.json, table `fold`). Every one of those folds can put a
// letter in a radical slot that was never a radical, and by the time a stem reaches
// this rung the evidence for which is gone. So a folded letter contributes every
// plausible pre-fold reading and the store decides between them — that is the whole
// of this rung's honesty about folds, and it is why there is no rule here about ة,
// about hamza seats, or about any particular word.
//
// final says the slot is the last letter of the stem. It matters because ة and ى
// are written only at the end of a word, so only there can the letter standing in
// the slot be one of them.
func radicalReadings(c rune, final bool) []rune {
	out := []rune{c}
	switch c {
	case 'و', 'ي':
		// ؤ and ئ fold to their seats. The seat is orthography; the radical is the
		// hamza it carries. ء is how a root spells that hamza and ا is how a corpus
		// keyed through this same normaliser spells it, because أ folds to ا — the
		// two are one reading under two spellings and neither is ours to pick.
		out = append(out, 'ء', 'ا')
		if final && c == 'ي' {
			// ى folds to ي too, and a root that ends in ى ends in a weak letter the
			// spelling does not name.
			out = append(out, 'و')
		}
	case 'ه':
		if final {
			// ة folds to ه. A feminine ending is not a radical at all, so under this
			// reading the root's third radical is not written: صلاة is ص ل و wearing
			// an ending, not ص ل ه.
			out = append(out, weakFinals...)
		}
	}
	return out
}

// apply reads the radicals a stem puts in this template's slots and returns every
// root they can be read as. An empty result means the shape does not fit.
func (t template) apply(stem []rune) []string {
	shape := []rune(t.shape)
	if len(shape) != len(stem) {
		return nil
	}
	var first, second, third rune
	for i, s := range shape {
		switch s {
		case 'ف':
			first = stem[i]
		case 'ع':
			second = stem[i]
		case 'ل':
			third = stem[i]
		default:
			if stem[i] != s {
				return nil
			}
		}
	}
	if t.doubled {
		third = second
	}
	// An alef is never a radical. A root writes its weak letter as و or ي, and the
	// alef standing in a hollow or defective word is the letter that replaced one of
	// them — the spelling does not say which, so this is a shape that fits rather
	// than a reading of it.
	if first == 'ا' || second == 'ا' || third == 'ا' {
		return nil
	}

	// A doubled shape ends in its second radical and مفاعله ends in a letter of its
	// own, so in neither is the stem's last letter the third radical.
	thirdIsFinal := shape[len(shape)-1] == 'ل'
	thirds := radicalReadings(third, thirdIsFinal)
	if thirdIsFinal && thirdRadicalIsOneReadingAmongSeveral(shape, stem, third) {
		thirds = append(thirds, weakFinals...)
	}

	var out []string
	for _, f := range radicalReadings(first, false) {
		for _, s := range radicalReadings(second, false) {
			for _, l := range thirds {
				out = append(out, string([]rune{f, s, l}))
			}
		}
	}
	return out
}

// thirdRadicalIsOneReadingAmongSeveral reports whether the letter this shape calls
// its third radical could just as well be something that is not a radical at all,
// in which case the weak readings belong beside it.
//
// Two spellings do it, neither of them a fold. A final hamza sitting on the
// pattern's own alef is either a radical — ق ر ء is a real root, so قراء really is
// قرء — or a weak third radical hardened by the long vowel in front of it, which is
// what دعاء is doing to د ع و. And a stem whose ending is an inflectional suffix the
// stripper refused to peel is inflection being read as a radical: بنات is ب ن ي
// wearing the feminine plural, not the root ب ن ت.
func thirdRadicalIsOneReadingAmongSeveral(shape, stem []rune, third rune) bool {
	if shape[len(shape)-1] != 'ل' {
		return false
	}
	if third == 'ء' && len(shape) > 1 && shape[len(shape)-2] == 'ا' {
		return true
	}
	return endsInUnpeelableSuffix(string(stem))
}

// matchPattern returns every root the standard templates can read out of a stem.
// It proposes; it never chooses. A template can say that a word fits a shape and
// can never say that the letters it yields are a root anyone has ever used, so the
// caller takes this set to the store and answers only for a reading the corpus
// confirms. An empty result means no template fits at all.
//
// The stem is expected in normalised orthography. Quadriliteral roots have no
// template here, and forms I, II and IX are spelled like the bare root, so a word
// in any of them is absent from the set rather than guessed at.
func matchPattern(stem string) []string {
	letters := []rune(stem)
	for _, r := range letters {
		if !unicode.IsLetter(r) || !unicode.Is(unicode.Arabic, r) {
			return nil
		}
	}

	var out []string
	for _, t := range templates {
		for _, reading := range t.apply(letters) {
			if !slices.Contains(out, reading) {
				out = append(out, reading)
			}
		}
	}
	return out
}
