package main

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

// markers holds the English a wazn contributes to a gloss regardless of the
// root. Those words are removed from a gloss before matching so a sense cannot
// earn credit from the pattern instead of the root.
//
// Only the rules the corpus measurably supports are listed here. Run
// "rootcheck reliability" for the measurement. Forms II and IV are left out
// because they overlap on the same English ("make", "cause") and each fires in
// under 3% of its glosses; III and VIII contribute no distinctive English at
// all; VII's "become" never appears; V's reflexives are enriched but fire in
// about 2% of its glosses, too rare to be a rule.
var markers = map[string][]string{
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

// LoadRoots reads every glossed, root-bearing word out of corpus.db and buckets
// it by root and slot.
func LoadRoots(dbPath string) (map[string]*Root, error) {
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.Query(`SELECT root_letters, gloss_en, COALESCE(form,''), COALESCE(morphology,'')
		FROM words
		WHERE root_letters IS NOT NULL AND root_letters <> ''
		  AND gloss_en IS NOT NULL AND trim(gloss_en) <> ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type key struct{ root, slot string }
	seen := map[key]map[string]int{}
	counts := map[string]int{}
	for rows.Next() {
		var root, gloss, form, morph string
		if err := rows.Scan(&root, &gloss, &form, &morph); err != nil {
			return nil, err
		}
		k := key{root, slotOf(form, stemFeatures(morph))}
		if seen[k] == nil {
			seen[k] = map[string]int{}
		}
		g := strings.ToLower(strings.TrimSpace(gloss))
		seen[k][g]++
		counts[root]++
		for _, t := range tokens(g) {
			if dispersion[t] == nil {
				dispersion[t] = map[string]bool{}
			}
			dispersion[t][root] = true
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := map[string]*Root{}
	for k, gs := range seen {
		r := out[k.root]
		if r == nil {
			r = &Root{Letters: k.root, Words: counts[k.root]}
			out[k.root] = r
		}
		list := make([]Gloss, 0, len(gs))
		for g, n := range gs {
			list = append(list, Gloss{Text: g, N: n})
		}
		sort.Slice(list, func(i, j int) bool { return list[i].Text < list[j].Text })
		r.Slots = append(r.Slots, Slot{Name: k.slot, Glosses: list})
	}
	for _, r := range out {
		sort.Slice(r.Slots, func(i, j int) bool { return r.Slots[i].Name < r.Slots[j].Name })
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: no glossed root-bearing words", dbPath)
	}
	return out, nil
}
