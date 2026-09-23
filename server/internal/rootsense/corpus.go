package rootsense

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	_ "modernc.org/sqlite"
)

// Slot is a group of a root's words that share a morphological shape. Senses
// are scored per slot so that one heavily attested form cannot carry a root on
// its own: a sense has to hold across the shapes the root appears in.
type Slot struct {
	Name    string
	Glosses []Gloss
}

// Gloss is one distinct English gloss and the number of word occurrences that
// carry it. The count is what separates what the corpus contains from what a
// reader meets: a root can hold twenty distinct glosses for one branch of its
// meaning and a single gloss for the branch that accounts for most of its
// occurrences.
type Gloss struct {
	Text string // distinct, lowercased
	N    int    // word occurrences carrying this gloss
	Word string // one of the words carrying it, for provenance
}

// Support is one word whose gloss a sense predicted. It is the provenance a
// shipped sense carries: the reader is told which of the root's own words the
// sense was checked against, not merely that a number came out high.
type Support struct {
	Word  string `json:"word"`
	Gloss string `json:"gloss"`
	Slot  string `json:"slot"`
}

type Root struct {
	Letters string
	Slots   []Slot
	Words   int // glossed word occurrences, all slots
}

// dispersion counts, for each gloss stem, how many distinct roots the corpus
// glosses with it. It is how the check tells generic English apart from a word
// that belongs to somebody else: "bring" and "down" are spread over twenty
// roots and carry no claim, while "unseen" and "believers" sit on one or two
// and naming them inside another root's sense is a claim about those roots.
//
// ponytail: package-level because this is a single-corpus CLI; make it a field
// on a corpus struct if a second corpus ever has to be open at once.
var dispersion = map[string]map[string]bool{}

// Markers holds the English a wazn contributes to a gloss regardless of the
// root. Those words are removed from a gloss before matching so a sense cannot
// earn credit from the pattern instead of the root.
//
// Only the rules the corpus measurably supports are listed here. Run
// "rootcheck reliability" for the measurement. Forms II and IV are left out
// because they overlap on the same English ("make", "cause") and each fires in
// under 3% of its glosses; III and VIII contribute no distinctive English at
// all; VII's "become" never appears; V's reflexives are enriched but fire in
// about 2% of its glosses, too rare to be a rule.
var Markers = map[string][]string{
	"form-X":    {"seek", "ask"},
	"form-VI":   {"each", "other", "another"},
	"pass-verb": {"been", "was", "were"},
	"act-pcpl":  {"who", "those", "ones"},
	"pass-pcpl": {"who", "those", "ones"},
}

func slotOf(form string, feats []string) string {
	has := func(f string) bool {
		for _, x := range feats {
			if x == f {
				return true
			}
		}
		return false
	}
	switch {
	case has("PCPL") && has("ACT"):
		return "act-pcpl"
	case has("PCPL") && has("PASS"):
		return "pass-pcpl"
	case has("VN"):
		return "verbal-noun"
	case has("PASS"):
		return "pass-verb"
	case form != "":
		return "form-" + form
	}
	return "noun"
}

func stemFeatures(morphology string) []string {
	var segs []struct {
		Features []string `json:"features"`
	}
	if json.Unmarshal([]byte(morphology), &segs) != nil {
		return nil
	}
	for _, s := range segs {
		for _, f := range s.Features {
			if f == "STEM" {
				return s.Features
			}
		}
	}
	return nil
}

// WordRow is one glossed, root-bearing word. It is what both callers have:
// the CLI reads them out of corpus.db, and the ETL gate holds them in memory
// before any database exists to read.
type WordRow struct {
	Root, Gloss, Text, Form, Morphology string
}

// LoadRoots reads every glossed, root-bearing word out of corpus.db.
func LoadRoots(dbPath string) (map[string]*Root, error) {
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.Query(`SELECT root_letters, gloss_en, text_ar, COALESCE(form,''), COALESCE(morphology,'')
		FROM words
		WHERE root_letters IS NOT NULL AND root_letters <> ''
		  AND gloss_en IS NOT NULL AND trim(gloss_en) <> ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var words []WordRow
	for rows.Next() {
		var w WordRow
		if err := rows.Scan(&w.Root, &w.Gloss, &w.Text, &w.Form, &w.Morphology); err != nil {
			return nil, err
		}
		words = append(words, w)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := Bucket(words)
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: no glossed root-bearing words", dbPath)
	}
	return out, nil
}

// Bucket groups words by root and morphological slot, counting how many
// occurrences carry each distinct gloss, and rebuilds the corpus-wide index of
// which roots each gloss word appears under.
func Bucket(words []WordRow) map[string]*Root {
	dispersion = map[string]map[string]bool{}
	rootsCache = map[string]map[string]bool{}

	type key struct{ root, slot string }
	type tally struct {
		n    int
		word string
	}
	seen := map[key]map[string]*tally{}
	counts := map[string]int{}
	for _, w := range words {
		if w.Root == "" || strings.TrimSpace(w.Gloss) == "" {
			continue
		}
		k := key{w.Root, slotOf(w.Form, stemFeatures(w.Morphology))}
		if seen[k] == nil {
			seen[k] = map[string]*tally{}
		}
		g := strings.ToLower(strings.TrimSpace(w.Gloss))
		t := seen[k][g]
		if t == nil {
			t = &tally{word: strings.TrimSpace(w.Text)}
			seen[k][g] = t
		}
		t.n++
		counts[w.Root]++
		for _, tok := range tokens(g) {
			if dispersion[tok] == nil {
				dispersion[tok] = map[string]bool{}
			}
			dispersion[tok][w.Root] = true
		}
	}

	out := map[string]*Root{}
	for k, gs := range seen {
		r := out[k.root]
		if r == nil {
			r = &Root{Letters: k.root, Words: counts[k.root]}
			out[k.root] = r
		}
		list := make([]Gloss, 0, len(gs))
		for g, t := range gs {
			list = append(list, Gloss{Text: g, N: t.n, Word: t.word})
		}
		sort.Slice(list, func(i, j int) bool { return list[i].Text < list[j].Text })
		r.Slots = append(r.Slots, Slot{Name: k.slot, Glosses: list})
	}
	for _, r := range out {
		sort.Slice(r.Slots, func(i, j int) bool { return r.Slots[i].Name < r.Slots[j].Name })
	}
	return out
}

// LoadNames counts, per root, the glossed occurrences the corpus tags as proper
// nouns, and how many of those carry a gloss word a sense could name.
//
// It exists to check a claim rather than to score anything. The tag looks like
// the way to find a root whose mass is a name, but it finds only 26 roots of
// 1642, and none of نفق, سجد, حجج, ثوب or طوي, whose heaviest branch is a
// derived noun the tag calls an ordinary one. What the branch term measures is
// the occurrences themselves, which sees all of them; the tag's job here is to
// show that it misses none of what the tag would have found.
func LoadNames(dbPath string) (map[string]int, map[string]int, error) {
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		return nil, nil, err
	}
	defer db.Close()
	rows, err := db.Query(`SELECT root_letters, gloss_en, COALESCE(morphology,'')
		FROM words
		WHERE root_letters IS NOT NULL AND root_letters <> ''
		  AND gloss_en IS NOT NULL AND trim(gloss_en) <> ''`)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	names, nameable := map[string]int{}, map[string]int{}
	for rows.Next() {
		var root, gloss, morph string
		if err := rows.Scan(&root, &gloss, &morph); err != nil {
			return nil, nil, err
		}
		isPN := false
		for _, f := range stemFeatures(morph) {
			if f == "POS:PN" {
				isPN = true
			}
		}
		if !isPN {
			continue
		}
		names[root]++
		if len(tokens(gloss)) > 0 {
			nameable[root]++
		}
	}
	return names, nameable, rows.Err()
}
