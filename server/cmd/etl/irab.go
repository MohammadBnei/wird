package main

import (
	"sort"
	"strings"
)

// Iʿrāb: the parsing of a word, segment by segment, built here rather than
// fetched. The input is the morphology file the ETL already reads — one line per
// segment, a TAG and a list of feature tokens — and the output is two tables:
// the vocabulary, and one row per segment naming which of it applies.
//
// One row per SEGMENT and not per word, because that is where the answer lives:
// case and mood are assigned by the syntax of the verse (GEN 12,629, ACC 10,331,
// NOM 8,954, MOOD:JUS 1,418, MOOD:SUBJ 1,330 in the shipped corpus), and a word
// carrying three segments has three different roles to say.
//
// The role NAMES are authored, not transcribed. Nothing in
// quranic-corpus-morphology-0.4.txt spells out what AMD, AVR, EXL, INL, PREV,
// RSLT, EQ, SUR or RET stand for — its header is two copyright blocks and its
// body is codes. The English is a reading of corpus.quran.com's own annotation
// vocabulary against the forms each code is actually attached to in the file;
// the French has no upstream at all. 142 pairs is review work for a person who
// knows both grammars, and no gate can tell you MOOD:JUS is *mode apocopé*
// rather than *mode jussif*. data/SOURCES.md says so in the row that covers it.

// IrabRow is one segment of one word: where it sits inside the word, the
// vocabulary code for its part of speech, and the rest of its codes.
//
// Features are space-joined rather than given a row each. A row per feature is
// 340,000 rows to say what 128,219 already say, and every reader of this table
// wants the whole segment at once.
type IrabRow struct {
	WordID   int64
	Position int // the segment's place inside the word, 1-based
	Code     string
	Features string
}

// irabRow reads one segment. LEM: and ROOT: are this word's own data rather
// than vocabulary, and POS: repeats the TAG column: measured over all 128,219
// segments, the two never disagree, and 50,304 segments (the prefixes and
// suffixes) carry no POS: at all. So the TAG is the one part of speech and the
// POS: token is dropped rather than shipped twice.
func irabRow(id int64, position int, seg morphSegment) IrabRow {
	feats := make([]string, 0, len(seg.Features))
	for _, ft := range seg.Features {
		if strings.HasPrefix(ft, "LEM:") || strings.HasPrefix(ft, "ROOT:") ||
			strings.HasPrefix(ft, "POS:") {
			continue
		}
		feats = append(feats, ft)
	}
	return IrabRow{WordID: id, Position: position, Code: posCode(seg.POS),
		Features: strings.Join(feats, " ")}
}

// posCode namespaces a TAG under the file's own POS: prefix. Without it the
// vocabulary collides with itself: the TAG `P` is a preposition while the
// feature `P` is a plural, `ACC` is a particle where the feature is a case, and
// `IMPV` is a prefixed lām where the feature is an aspect.
func posCode(tag string) string { return "POS:" + tag }

// IrabRole is one row of the vocabulary. A role ships in both languages or
// neither — Corpus.Check refuses an empty half — because a French reader shown
// an English parsing has been shown someone else's app.
type IrabRole struct {
	Code, En, Fr string
}

// IrabRoles is the vocabulary in code order, which is the order it is written
// in: a stable order is what makes two builds of the same input comparable.
func IrabRoles() []IrabRole {
	out := make([]IrabRole, 0, len(irabRoles))
	for code, names := range irabRoles {
		out = append(out, IrabRole{Code: code, En: names[0], Fr: names[1]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Code < out[j].Code })
	return out
}

// The vocabulary: every code the morphology file writes that a reader is shown,
// in English and in French. 45 parts of speech and 97 features.
//
// ponytail: a map literal, read once at build time. It is not worth a file
// format of its own until a translator who does not write Go needs to edit it.
var irabRoles = map[string][2]string{
	// Parts of speech — the TAG column.
	"POS:N":    {"Noun", "Nom"},
	"POS:PN":   {"Proper noun", "Nom propre"},
	"POS:ADJ":  {"Adjective", "Adjectif"},
	"POS:IMPN": {"Imperative verbal noun", "Nom verbal à l’impératif"},
	"POS:V":    {"Verb", "Verbe"},
	"POS:PRON": {"Personal pronoun", "Pronom personnel"},
	"POS:DEM":  {"Demonstrative pronoun", "Pronom démonstratif"},
	"POS:REL":  {"Relative pronoun", "Pronom relatif"},
	"POS:T":    {"Time adverb", "Adverbe de temps"},
	"POS:LOC":  {"Location adverb", "Adverbe de lieu"},
	"POS:P":    {"Preposition", "Préposition"},
	"POS:DET":  {"Determiner", "Déterminant"},
	"POS:CONJ": {"Coordinating conjunction", "Conjonction de coordination"},
	"POS:SUB":  {"Subordinating conjunction", "Conjonction de subordination"},
	"POS:ACC":  {"Accusative particle", "Particule d’accusatif"},
	"POS:AMD":  {"Amendment particle", "Particule de rectification"},
	"POS:ANS":  {"Answer particle", "Particule de réponse"},
	"POS:AVR":  {"Aversion particle", "Particule de dissuasion"},
	"POS:CAUS": {"Particle of cause", "Particule de cause"},
	"POS:CERT": {"Particle of certainty", "Particule de certitude"},
	"POS:CIRC": {"Circumstantial particle", "Particule de circonstance"},
	"POS:COM":  {"Comitative particle", "Particule d’accompagnement"},
	"POS:COND": {"Conditional particle", "Particule conditionnelle"},
	"POS:EMPH": {"Emphatic particle", "Particule d’emphase"},
	"POS:EQ":   {"Equalization particle", "Particule d’égalité"},
	"POS:EXH":  {"Exhortation particle", "Particule d’exhortation"},
	"POS:EXL":  {"Explanation particle", "Particule d’explication"},
	"POS:EXP":  {"Exceptive particle", "Particule d’exception"},
	"POS:FUT":  {"Future particle", "Particule du futur"},
	"POS:IMPV": {"Imperative particle", "Particule d’impératif"},
	"POS:INC":  {"Inceptive particle", "Particule d’inchoation"},
	"POS:INL":  {"Qur’anic initials", "Lettres liminaires du Coran"},
	"POS:INT":  {"Interpretation particle", "Particule interprétative"},
	"POS:INTG": {"Interrogative particle", "Particule interrogative"},
	"POS:NEG":  {"Negative particle", "Particule de négation"},
	"POS:PREV": {"Preventive particle", "Particule préventive"},
	"POS:PRO":  {"Prohibition particle", "Particule de prohibition"},
	"POS:PRP":  {"Purpose particle", "Particule de but"},
	"POS:REM":  {"Resumption particle", "Particule de reprise"},
	"POS:RES":  {"Restriction particle", "Particule de restriction"},
	"POS:RET":  {"Retraction particle", "Particule de rétractation"},
	"POS:RSLT": {"Result particle", "Particule de résultat"},
	"POS:SUP":  {"Supplemental particle", "Particule supplémentaire"},
	"POS:SUR":  {"Surprise particle", "Particule de surprise"},
	"POS:VOC":  {"Vocative particle", "Particule du vocatif"},

	// Where the segment sits inside the word.
	"PREFIX": {"Prefix", "Préfixe"},
	"STEM":   {"Stem", "Radical"},
	"SUFFIX": {"Suffix", "Suffixe"},

	// The derived verb forms. The file tags II to XII and never I; a verb with
	// no tag is Form I, which is why there is no code for it here.
	"(II)":   {"Form II", "Forme II"},
	"(III)":  {"Form III", "Forme III"},
	"(IV)":   {"Form IV", "Forme IV"},
	"(V)":    {"Form V", "Forme V"},
	"(VI)":   {"Form VI", "Forme VI"},
	"(VII)":  {"Form VII", "Forme VII"},
	"(VIII)": {"Form VIII", "Forme VIII"},
	"(IX)":   {"Form IX", "Forme IX"},
	"(X)":    {"Form X", "Forme X"},
	"(XI)":   {"Form XI", "Forme XI"},
	"(XII)":  {"Form XII", "Forme XII"},

	// Aspect, mood, voice and the two derivations.
	"PERF":      {"Perfect", "Accompli"},
	"IMPF":      {"Imperfect", "Inaccompli"},
	"IMPV":      {"Imperative", "Impératif"},
	"MOOD:JUS":  {"Jussive mood", "Mode apocopé"},
	"MOOD:SUBJ": {"Subjunctive mood", "Mode subjonctif"},
	"ACT":       {"Active", "Actif"},
	"PASS":      {"Passive", "Passif"},
	"PCPL":      {"Participle", "Participe"},
	"VN":        {"Verbal noun", "Nom verbal"},
	"SP:<in~":   {"Of the inna family", "De la famille de inna"},
	"SP:kaAn":   {"Of the kāna family", "De la famille de kāna"},
	"SP:kaAd":   {"Of the kāda family", "De la famille de kāda"},

	// Case, and whether the noun is defined.
	"NOM":   {"Nominative", "Nominatif"},
	"ACC":   {"Accusative", "Accusatif"},
	"GEN":   {"Genitive", "Génitif"},
	"INDEF": {"Indefinite", "Indéfini"},

	// A noun's gender and number. M, F and P alone are the cases where the file
	// records one without the other.
	"M":  {"Masculine", "Masculin"},
	"F":  {"Feminine", "Féminin"},
	"P":  {"Plural", "Pluriel"},
	"MS": {"Masculine singular", "Masculin singulier"},
	"MD": {"Masculine dual", "Masculin duel"},
	"MP": {"Masculine plural", "Masculin pluriel"},
	"FS": {"Feminine singular", "Féminin singulier"},
	"FD": {"Feminine dual", "Féminin duel"},
	"FP": {"Feminine plural", "Féminin pluriel"},

	// A verb's person, gender and number.
	"1S":  {"1st person singular", "1re personne du singulier"},
	"1P":  {"1st person plural", "1re personne du pluriel"},
	"2MS": {"2nd person masculine singular", "2e personne du masculin singulier"},
	"2MD": {"2nd person masculine dual", "2e personne du masculin duel"},
	"2MP": {"2nd person masculine plural", "2e personne du masculin pluriel"},
	"2FS": {"2nd person feminine singular", "2e personne du féminin singulier"},
	"2FD": {"2nd person feminine dual", "2e personne du féminin duel"},
	"2FP": {"2nd person feminine plural", "2e personne du féminin pluriel"},
	"2D":  {"2nd person dual", "2e personne du duel"},
	"3MS": {"3rd person masculine singular", "3e personne du masculin singulier"},
	"3MD": {"3rd person masculine dual", "3e personne du masculin duel"},
	"3MP": {"3rd person masculine plural", "3e personne du masculin pluriel"},
	"3FS": {"3rd person feminine singular", "3e personne du féminin singulier"},
	"3FD": {"3rd person feminine dual", "3e personne du féminin duel"},
	"3FP": {"3rd person feminine plural", "3e personne du féminin pluriel"},
	"3D":  {"3rd person dual", "3e personne du duel"},

	// The attached pronouns.
	"PRON:1S":  {"1st person singular pronoun", "Pronom de la 1re personne du singulier"},
	"PRON:1P":  {"1st person plural pronoun", "Pronom de la 1re personne du pluriel"},
	"PRON:2MS": {"2nd person masculine singular pronoun", "Pronom de la 2e personne du masculin singulier"},
	"PRON:2MD": {"2nd person masculine dual pronoun", "Pronom de la 2e personne du masculin duel"},
	"PRON:2MP": {"2nd person masculine plural pronoun", "Pronom de la 2e personne du masculin pluriel"},
	"PRON:2FS": {"2nd person feminine singular pronoun", "Pronom de la 2e personne du féminin singulier"},
	"PRON:2FD": {"2nd person feminine dual pronoun", "Pronom de la 2e personne du féminin duel"},
	"PRON:2FP": {"2nd person feminine plural pronoun", "Pronom de la 2e personne du féminin pluriel"},
	"PRON:2D":  {"2nd person dual pronoun", "Pronom de la 2e personne du duel"},
	"PRON:3MS": {"3rd person masculine singular pronoun", "Pronom de la 3e personne du masculin singulier"},
	"PRON:3MD": {"3rd person masculine dual pronoun", "Pronom de la 3e personne du masculin duel"},
	"PRON:3MP": {"3rd person masculine plural pronoun", "Pronom de la 3e personne du masculin pluriel"},
	"PRON:3FS": {"3rd person feminine singular pronoun", "Pronom de la 3e personne du féminin singulier"},
	"PRON:3FD": {"3rd person feminine dual pronoun", "Pronom de la 3e personne du féminin duel"},
	"PRON:3FP": {"3rd person feminine plural pronoun", "Pronom de la 3e personne du féminin pluriel"},
	"PRON:3D":  {"3rd person dual pronoun", "Pronom de la 3e personne du duel"},

	// The prefixed particles, named by the letter a reader sees at the front of
	// the word and by what that letter is doing there.
	"Al+":     {"Prefixed definite article al-", "Article défini al- préfixé"},
	"bi+":     {"Prefixed preposition bi-", "Préposition bi- préfixée"},
	"ka+":     {"Prefixed preposition ka-", "Préposition ka- préfixée"},
	"sa+":     {"Prefixed future particle sa-", "Particule du futur sa- préfixée"},
	"ta+":     {"Prefixed oath tā-", "Tā de serment préfixé"},
	"ha+":     {"Prefixed particle hā-", "Particule hā- préfixée"},
	"ya+":     {"Prefixed vocative yā", "Yā du vocatif préfixé"},
	"l:P+":    {"Prefixed preposition lām", "Lām préposition préfixé"},
	"l:EMPH+": {"Prefixed emphatic lām", "Lām d’emphase préfixé"},
	"l:IMPV+": {"Prefixed imperative lām", "Lām d’impératif préfixé"},
	"l:PRP+":  {"Prefixed purpose lām", "Lām de but préfixé"},
	"w:CONJ+": {"Prefixed conjunction wāw", "Wāw de coordination préfixé"},
	"w:REM+":  {"Prefixed resumption wāw", "Wāw de reprise préfixé"},
	"w:CIRC+": {"Prefixed circumstantial wāw", "Wāw de circonstance préfixé"},
	"w:COM+":  {"Prefixed comitative wāw", "Wāw d’accompagnement préfixé"},
	"w:P+":    {"Prefixed oath wāw", "Wāw de serment préfixé"},
	"w:SUP+":  {"Prefixed supplemental wāw", "Wāw supplémentaire préfixé"},
	"f:CONJ+": {"Prefixed conjunction fa", "Fā de coordination préfixé"},
	"f:REM+":  {"Prefixed resumption fa", "Fā de reprise préfixé"},
	"f:RSLT+": {"Prefixed result fa", "Fā de résultat préfixé"},
	"f:CAUS+": {"Prefixed causal fa", "Fā de cause préfixé"},
	"f:SUP+":  {"Prefixed supplemental fa", "Fā supplémentaire préfixé"},
	"A:INTG+": {"Prefixed interrogative alif", "Alif interrogatif préfixé"},
	"A:EQ+":   {"Prefixed equalization alif", "Alif d’égalité préfixé"},

	// The two suffixed particles.
	"+n:EMPH": {"Suffixed emphatic nūn", "Nūn d’emphase suffixé"},
	"+VOC":    {"Suffixed vocative", "Suffixe du vocatif"},
}
