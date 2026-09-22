package root

import (
	"fmt"
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
// morphological analyser over a vowelled corpus, which is the only thing that can
// decide the readings this rung deliberately refuses to choose between.
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

// template is one shape, plus what a weak root does to the spelling of it.
type template struct {
	shape string

	// doubled marks the spelling a root takes when its last two radicals are the
	// same letter and are written once: است + ر-د-د is استرد. The third radical is
	// still readable, because it is the second one again.
	doubled bool

	// hidden marks a shape that fits but keeps one of its radicals to itself, so
	// the match is a reason to stay silent rather than a reading. Two spellings do
	// this: a form VIII verb whose first radical is و, ي or ت loses it into the
	// pattern's own ت (و-ص-ل is written اتصل), and a hollow root writes its middle
	// radical as an alef (ق-و-م gives مقام).
	hidden bool
}

// hollowSpellings are shapes a hollow root produces that another template also
// fits. مقام is ق-و-م under maf3al, and is spelled exactly like fa33aal over
// م-ق-م. Nothing in the letters chooses between them, so both readings go.
var hollowSpellings = []string{"مفال"}

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
		if strings.Contains(s, "فت") {
			add(template{shape: strings.Replace(s, "فت", "ت", 1), hidden: true})
		}
	}
	for _, s := range hollowSpellings {
		add(template{shape: s, hidden: true})
	}
	return out
}

// weakFinals are the letters a defective root writes as its third radical. A
// spelling that may be hiding one of them yields a reading for each, because
// nothing in the letters says which.
var weakFinals = []rune{'و', 'ي'}

// apply reads the radicals a stem puts in this template's slots. The second
// result says whether the shape fits at all. A shape that fits and yields no
// readings is one whose radicals cannot be read back out of the spelling; a shape
// that yields several is one the spelling does not choose between.
func (t template) apply(stem []rune) ([]string, bool) {
	shape := []rune(t.shape)
	if len(shape) != len(stem) {
		return nil, false
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
				return nil, false
			}
		}
	}
	if t.hidden {
		return nil, true
	}
	if t.doubled {
		third = second
	}
	// An alef is never a radical. A root writes its weak letter as و or ي, and the
	// alef standing in a hollow or defective word is the letter that replaced one of
	// them — the spelling does not say which, so this is a shape that fits rather
	// than a reading of it.
	if first == 'ا' || second == 'ا' || third == 'ا' {
		return nil, false
	}

	readings := []string{string([]rune{first, second, third})}
	if thirdRadicalIsOneReadingAmongSeveral(shape, stem, third) {
		for _, w := range weakFinals {
			readings = append(readings, string([]rune{first, second, w}))
		}
	}
	return readings, true
}

// thirdRadicalIsOneReadingAmongSeveral reports whether the letter this shape
// calls its third radical could just as well be something that is not a radical
// at all, in which case the shape owes the caller every reading rather than one.
//
// Two spellings do it. A final hamza sitting on the pattern's own alef is either
// a radical — ق ر ء is a real root, so قراء really is قرء — or a weak third radical
// hardened by the long vowel in front of it, which is what دعاء is doing to د ع و.
// And a stem whose ending is an inflectional suffix the stripper refused to peel
// is inflection being read as a radical: بنات is ب ن ي wearing the feminine
// plural, not the root ب ن ت. Both readings are ordinary Arabic and the
// unvowelled spelling chooses neither.
func thirdRadicalIsOneReadingAmongSeveral(shape, stem []rune, third rune) bool {
	// A doubled shape ends in its second radical and مفاعله ends in a letter of
	// its own, so in both the stem's last letter is not the third radical and
	// neither reading below is about it.
	if shape[len(shape)-1] != 'ل' {
		return false
	}
	if third == 'ء' && len(shape) > 1 && shape[len(shape)-2] == 'ا' {
		return true
	}
	return endsInUnpeelableSuffix(string(stem))
}

// uncertainPatternError is a miss, not an answer. The stem fits the templates in
// more than one way, or in a way that hides one of its radicals, and this rung may
// never hand a reader a root it merely prefers. Candidates carries the readings
// that did come out, so a caller can say what was considered.
type uncertainPatternError struct {
	Stem       string
	Candidates []string
}

func (e *uncertainPatternError) Error() string {
	if len(e.Candidates) == 0 {
		return fmt.Sprintf("jidhr: the shape of %q hides which of its letters are radicals", e.Stem)
	}
	return fmt.Sprintf("jidhr: %q reads as more than one root (%s)", e.Stem, strings.Join(e.Candidates, ", "))
}

func (e *uncertainPatternError) Unwrap() error { return ErrNotFound }

// matchPattern reads the radicals out of a stem by matching it against the
// standard templates. It returns ErrNotFound when no template fits: a borrowed
// name has no root, and inventing one would teach the reader something false. It
// returns the same miss carrying candidates when several templates fit, because a
// shape that reads two ways is evidence for neither and this is the one rung that
// can be confidently wrong.
//
// The stem is expected in normalised orthography. Quadriliteral roots have no
// template here at all, and hollow roots, defective roots written with a final
// alef or a final hamza, words wearing a suffix too short to peel, and forms I,
// II and IX all miss by design — the comments above say why for
// each, and a miss is what this rung owes a word it cannot read.
func matchPattern(stem string) (string, error) {
	letters := []rune(stem)
	for _, r := range letters {
		if !unicode.IsLetter(r) || !unicode.Is(unicode.Arabic, r) {
			return "", ErrNotFound
		}
	}

	var readings []string
	incomplete := false
	for _, t := range templates {
		fitted, fits := t.apply(letters)
		if !fits {
			continue
		}
		if len(fitted) == 0 {
			incomplete = true
			continue
		}
		for _, reading := range fitted {
			if !slices.Contains(readings, reading) {
				readings = append(readings, reading)
			}
		}
	}

	switch {
	case incomplete || len(readings) > 1:
		return "", &uncertainPatternError{Stem: stem, Candidates: readings}
	case len(readings) == 1:
		return readings[0], nil
	default:
		return "", ErrNotFound
	}
}
