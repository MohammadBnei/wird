package root

import (
	"slices"
	"strings"
)

// minStem is the shortest stem affix stripping may produce. Three is the number of
// radicals in an Arabic root, and peeling past it is how a stripper invents a root
// out of a radical that merely looked like a clitic. A hollow or assimilated verb
// really can surface with two letters — قم for قوم — but putting the missing
// radical back is template work, which is rung five rather than this rung.
const minStem = 3

// stripPrefixes and stripSuffixes are written in normalised orthography — no
// diacritics, bare alef, ha for ta marbuta — because that is how the word arrives
// here and how the store is keyed.
var stripPrefixes = []struct {
	text string
	// before, when set, lists the letters this prefix may sit on. A particle that
	// attaches to only one word class is worth spelling out: stripped
	// unconditionally, it comes off every noun that happens to start with its
	// letter.
	before string
}{
	{text: "ال"},
	{text: "و"}, {text: "ف"},
	{text: "ب"}, {text: "ك"}, {text: "ل"},
	{text: "س", before: "يتنا"},
	{text: "ي"}, {text: "ت"}, {text: "ن"}, {text: "ا"},
}

var stripSuffixes = []string{
	"هما", "كما", "تما",
	"ها", "هم", "هن", "كم", "كن", "نا", "ني", "تم", "تن",
	"وا", "ون", "ين", "ان", "ات",
	"ه", "ك", "ي", "ت", "ا",
}

// endsInUnpeelableSuffix reports whether a word ends in an inflectional suffix
// that stripAffixes declined to peel because peeling it would leave fewer letters
// than a root has. Those letters are then inflection to this rung and root
// material to the pattern rung, and that disagreement is how بنات came back as
// the root ب ن ت: ات would not come off four letters, so the template read the
// ت as a radical. Single-letter suffixes are not counted — ك and ت and ه are
// among the commonest radicals in the language, and refusing every word that ends
// in one would refuse most of it.
func endsInUnpeelableSuffix(word string) bool {
	rs := []rune(word)
	for _, q := range stripSuffixes {
		n := len([]rune(q))
		if n < 2 || len(rs) < n || len(rs)-n >= minStem {
			continue
		}
		if string(rs[len(rs)-n:]) == q {
			return true
		}
	}
	return false
}

// stripAffixes peels clitics and inflection off a normalised word and returns the
// candidate stems, most likely first. This is the rung that makes any Arabic word
// resolvable rather than only the forms the Qur'anic corpus attests, so it returns
// several stems and lets the store decide which one exists.
//
// It returns ErrNotFound when the word has nothing to peel, which the ladder reads
// as a miss and not as a broken rung.
func stripAffixes(word string) ([]string, error) {
	rs := []rune(word)

	// Every candidate is a contiguous span of the original word, so peeling is a
	// walk over spans and it terminates: each step shortens the span.
	type span struct{ i, j, steps int }
	whole := span{0, len(rs), 0}
	seen := map[[2]int]bool{{whole.i, whole.j}: true}
	queue := []span{whole}
	var found []span

	push := func(s span) {
		key := [2]int{s.i, s.j}
		if seen[key] {
			return
		}
		seen[key] = true
		queue = append(queue, s)
		found = append(found, s)
	}

	for len(queue) > 0 {
		s := queue[0]
		queue = queue[1:]

		for _, p := range stripPrefixes {
			n := len([]rune(p.text))
			if s.j-s.i-n < minStem || string(rs[s.i:s.i+n]) != p.text {
				continue
			}
			if p.before != "" && !strings.ContainsRune(p.before, rs[s.i+n]) {
				continue
			}
			push(span{s.i + n, s.j, s.steps + 1})
		}

		for _, q := range stripSuffixes {
			n := len([]rune(q))
			if s.j-s.i-n < minStem || string(rs[s.j-n:s.j]) != q {
				continue
			}
			push(span{s.i, s.j - n, s.steps + 1})
		}
	}

	if len(found) == 0 {
		return nil, ErrNotFound
	}

	slices.SortFunc(found, func(a, b span) int {
		// Fewest letters peeled first, so the least aggressive reading the store
		// recognises is the one that wins. On a tie, peel the end before the
		// front: a word's first letter is a radical far more often than its last,
		// because the suffixes worth peeling are inflection while the prefixes are
		// single letters that are also among the commonest radicals.
		if d := (b.j - b.i) - (a.j - a.i); d != 0 {
			return d
		}
		if d := a.i - b.i; d != 0 {
			return d
		}
		return a.steps - b.steps
	})

	// ponytail: the store is the arbiter, and it only knows whether a stem exists,
	// not how likely it is. So كتاب, absent from the corpus, still yields تاب and
	// the root توب if the corpus happens to hold it. Ranking candidates by corpus
	// frequency is the fix, and it needs an ingested corpus to rank against.
	out := make([]string, 0, len(found))
	taken := make(map[string]bool, len(found))
	for _, s := range found {
		stem := string(rs[s.i:s.j])
		if taken[stem] {
			continue
		}
		taken[stem] = true
		out = append(out, stem)
	}
	return out, nil
}
