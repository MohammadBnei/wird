package lane

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Lane's Lexicon, made reachable by root.
//
// The sense of a root is written from established lexicography rather than
// derived from the corpus, so whoever writes it has to be able to read Lane's
// article for that root. Nothing here ships: `data/raw/lane` is gitignored, the
// text is consulted and never quoted, and only Wird's own sentences reach
// corpus.db. docs/research/lane-lexicon.md settled why that line is where it is — facts
// about a word are not copyrightable and a sentence of Lane's is.
//
// **Do not key on `div2/@n`.** That index is incomplete and in places wrong, and
// a naive join silently loses real articles: دبر has no division of its own and
// sits inside دبخ's, نوم is filed under the vocalised past tense `nAm`, and 81
// keys are ranges standing for several roots. The five strategies below are what
// the measurement in that document actually used, and they reach 1,582 of 1,642
// roots covering 99.2% of Qurʼanic root occurrences.

// Perseus writes Lane's Arabic in a Buckwalter variant: A^ is hamza seated on
// alef, y^ on ya, w^ on waw, A a bare alef, Y alef maqsura, the rest the usual
// 28 letters.
var two = map[string]rune{"A^": 'أ', "y^": 'ئ', "w^": 'ؤ'}

var one = map[byte]rune{
	'A': 'ا', 'Y': 'ى', 'b': 'ب', 't': 'ت', 'v': 'ث', 'j': 'ج', 'H': 'ح',
	'x': 'خ', 'd': 'د', '*': 'ذ', 'r': 'ر', 'z': 'ز', 's': 'س', '$': 'ش',
	'S': 'ص', 'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع', 'g': 'غ', 'f': 'ف',
	'q': 'ق', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'h': 'ه', 'w': 'و',
	'y': 'ي',
}

// Every hamza folds onto أ and alef maqsura onto ي, on both sides. The published
// root alphabet folds hamza the same way, so a join has to fold rather than
// assume — see the note in data/SOURCES.md about قرأ and لؤلؤ.
var hamza = strings.NewReplacer(
	"ا", "أ", "إ", "أ", "آ", "أ", "ؤ", "أ", "ئ", "أ", "ء", "أ", "ى", "ي",
)

func arabic(key string) string {
	var b strings.Builder
	for i := 0; i < len(key); {
		if i+2 <= len(key) {
			if r, ok := two[key[i:i+2]]; ok {
				b.WriteRune(r)
				i += 2
				continue
			}
		}
		r, ok := one[key[i]]
		if !ok {
			return "" // not a letter a root is built from
		}
		b.WriteRune(r)
		i++
	}
	return b.String()
}

func Fold(root string) string { return hamza.Replace(root) }

// Prefix for the second index: every division is also held under its raw @n key,
// because a key Lane vocalised is a key no Arabic fold can reach. The prefix
// cannot collide with a folded root, which is Arabic letters only.
const rawKey = "@"

// The eighteen roots whose article is real but filed under another division's
// key, measured and listed in docs/research/lane-lexicon.md. Refusing these would throw
// away knowledge this repository already has: دبر is a common root and its
// article — dabarahu, duburN, Adbr, Astdbrhu and six more — sits inside دبخ's
// division, which is two roots merged into one. نوم is filed under the vocalised
// past tense نام. Keyed by our folded root, valued by the Lane division key in
// Arabic after the same fold.
//
// Hand-written because it was hand-measured. A rule that found these would have
// to guess at Lane's filing, and the guess is what docs/research/lane-lexicon.md warns
// against: do not key an implementation on the division index.
var filedElsewhere = map[string]string{
	"بقل": "baqala", "تيه": "tyn", "جحد": "Hd", "جحم": "jHfl", "جهز": "Hhz",
	"جهل": "jahila", "حرث": "Hrb", "حوج": "HaAja", "خبت": "xbv", "دبر": "dbx",
	"دور": "dwrd", "شأم": "$m", "نحت": "nxt", "نصت": "nSb", "نضخ": "nDH",
	"نفح": "tfH", "نوم": "nAm", "هأت": "hyt",
}

var (
	divRe   = regexp.MustCompile(`(<div2\b[^>]*>)`)
	nRe     = regexp.MustCompile(`\bn="([^"]*)"`)
	tagRe   = regexp.MustCompile(`<[^>]*>`)
	spaceRe = regexp.MustCompile(`\s+`)
	joinRe  = regexp.MustCompile(`\s+(?:and|or)\s+`)
)

// Articles reads every root division in the Perseus XML and returns the
// prose of each, keyed by the folded Arabic of its division key. A key naming
// several roots contributes its prose to each of them, which is why this
// accumulates rather than assigns.
func Articles(dir string) (map[string]string, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.xml"))
	if err != nil {
		return nil, err
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("no XML in %s: clone the `originals` branch of "+
			"github.com/laneslexicon/lexicon_xml there. It is gitignored on purpose — "+
			"Lane is consulted, never committed and never shipped", dir)
	}
	sort.Strings(paths)
	out := map[string]string{}
	for _, path := range paths {
		src, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		parts := divRe.Split(string(src), -1)
		heads := divRe.FindAllStringSubmatch(string(src), -1)
		for i, head := range heads {
			if !strings.Contains(head[1], `type="root"`) {
				continue
			}
			n := nRe.FindStringSubmatch(head[1])
			if n == nil || i+1 >= len(parts) {
				continue
			}
			body, _, _ := strings.Cut(parts[i+1], "</div2>")
			prose := strings.TrimSpace(spaceRe.ReplaceAllString(
				tagRe.ReplaceAllString(body, " "), " "))
			for _, key := range joinRe.Split(strings.ReplaceAll(n[1], "&amp;c.", ""), -1) {
				key = strings.TrimSpace(key)
				if key == "" || strings.HasPrefix(key, "Quasi") {
					continue
				}
				out[rawKey+key] += " " + prose
				if ar := arabic(key); ar != "" {
					out[Fold(ar)] += " " + prose
				}
			}
		}
	}
	return out, nil
}

// Look answers which division holds a root's article, and how it was reached.
// The four fallbacks are not cleverness: Lane files a geminate root under its two
// distinct letters, a final-weak root likewise, and a reduplicated root under its
// first half.
func Look(articles map[string]string, root string) (string, string) {
	f := Fold(root)
	r := []rune(f)
	if _, ok := articles[f]; ok {
		return f, "exact"
	}
	if key, ok := filedElsewhere[f]; ok {
		// By the raw division key, not its Arabic: several of these keys are
		// vocalised — jahila, baqala, HaAja, dwrd — so arabic rejects their
		// vowels and they are indexed under no Arabic key at all.
		if _, ok := articles[rawKey+key]; ok {
			return rawKey + key, "filed under " + key
		}
	}
	two := string(r[:min(2, len(r))])
	if _, ok := articles[two]; !ok {
		return "", ""
	}
	switch {
	case len(r) == 3 && r[1] == r[2]:
		return two, "geminate"
	case len(r) == 4 && string(r[:2]) == string(r[2:]):
		return two, "reduplicated"
	case len(r) == 3 && strings.ContainsRune("ويأ", r[2]):
		return two, "final-weak"
	}
	return "", ""
}

// Print prints one root's article for whoever is writing its sense.
func Print(w io.Writer, dir, root string) error {
	articles, err := Articles(dir)
	if err != nil {
		return err
	}
	key, how := Look(articles, root)
	if key == "" {
		return fmt.Errorf("%s reaches no Lane division. 31 roots do not, and 18 of "+
			"those have their headword inside another root's division — "+
			"docs/research/lane-lexicon.md names every one. Write this sense without Lane and "+
			"say so", root)
	}
	prose := strings.TrimSpace(articles[key])
	fmt.Fprintf(w, "%s → %s (%s, %d chars)\n\n", root, key, how, len(prose))
	if len(prose) < 200 {
		fmt.Fprintf(w, "STUB. Lane has effectively nothing here; 200 characters is the "+
			"line docs/research/lane-lexicon.md measured everything against.\n\n")
	}
	fmt.Fprintln(w, prose)
	return nil
}
