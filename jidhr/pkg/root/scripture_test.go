package root

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// scriptureWord is one word of the Qur'an as app/assets/corpus.db, the authority,
// records it: the Uthmani spelling the mushaf prints and the corpus stores, the
// ordinary spelling a reader types on a phone keyboard, and the root the
// morphology records — empty for the pronouns and particles the morphology gives
// no root at all, which no corpus growth will ever make resolvable.
type scriptureWord struct {
	ayah     string
	uthmani  string
	ordinary string
	root     string
}

// theSurahsAReaderMeetsFirst is every word of Al-Fatiha, of Al-Ikhlas, of An-Nas,
// and of the first five ayat of Al-Alaq: the surahs a reader meets first, in every
// prayer and on the first screen of the app. The Uthmani column and the roots are
// read out of corpus.db; the ordinary column is what a person types.
var theSurahsAReaderMeetsFirst = []scriptureWord{
	{"1:1", "بِسْمِ", "بسم", "سمو"},
	{"1:1", "ٱللَّهِ", "الله", "أله"},
	{"1:1", "ٱلرَّحْمَـٰنِ", "الرحمن", "رحم"},
	{"1:1", "ٱلرَّحِيمِ", "الرحيم", "رحم"},
	{"1:2", "ٱلْحَمْدُ", "الحمد", "حمد"},
	{"1:2", "لِلَّهِ", "لله", "أله"},
	{"1:2", "رَبِّ", "رب", "ربب"},
	{"1:2", "ٱلْعَـٰلَمِينَ", "العالمين", "علم"},
	{"1:3", "ٱلرَّحْمَـٰنِ", "الرحمن", "رحم"},
	{"1:3", "ٱلرَّحِيمِ", "الرحيم", "رحم"},
	{"1:4", "مَـٰلِكِ", "مالك", "ملك"},
	{"1:4", "يَوْمِ", "يوم", "يوم"},
	{"1:4", "ٱلدِّينِ", "الدين", "دين"},
	{"1:5", "إِيَّاكَ", "إياك", ""},
	{"1:5", "نَعْبُدُ", "نعبد", "عبد"},
	{"1:5", "وَإِيَّاكَ", "وإياك", ""},
	{"1:5", "نَسْتَعِينُ", "نستعين", "عون"},
	{"1:6", "ٱهْدِنَا", "اهدنا", "هدي"},
	{"1:6", "ٱلصِّرَٰطَ", "الصراط", "صرط"},
	{"1:6", "ٱلْمُسْتَقِيمَ", "المستقيم", "قوم"},
	{"1:7", "صِرَٰطَ", "صراط", "صرط"},
	{"1:7", "ٱلَّذِينَ", "الذين", ""},
	{"1:7", "أَنْعَمْتَ", "أنعمت", "نعم"},
	{"1:7", "عَلَيْهِمْ", "عليهم", ""},
	{"1:7", "غَيْرِ", "غير", "غير"},
	{"1:7", "ٱلْمَغْضُوبِ", "المغضوب", "غضب"},
	{"1:7", "عَلَيْهِمْ", "عليهم", ""},
	{"1:7", "وَلَا", "ولا", ""},
	{"1:7", "ٱلضَّآلِّينَ", "الضالين", "ضلل"},
	{"112:1", "قُلْ", "قل", "قول"},
	{"112:1", "هُوَ", "هو", ""},
	{"112:1", "ٱللَّهُ", "الله", "أله"},
	{"112:1", "أَحَدٌ", "أحد", "أحد"},
	{"112:2", "ٱللَّهُ", "الله", "أله"},
	{"112:2", "ٱلصَّمَدُ", "الصمد", "صمد"},
	{"112:3", "لَمْ", "لم", ""},
	{"112:3", "يَلِدْ", "يلد", "ولد"},
	{"112:3", "وَلَمْ", "ولم", ""},
	{"112:3", "يُولَدْ", "يولد", "ولد"},
	{"112:4", "وَلَمْ", "ولم", ""},
	{"112:4", "يَكُن", "يكن", "كون"},
	{"112:4", "لَّهُۥ", "له", ""},
	{"112:4", "كُفُوًا", "كفوا", "كفأ"},
	{"112:4", "أَحَدٌۢ", "أحد", "أحد"},
	{"114:1", "قُلْ", "قل", "قول"},
	{"114:1", "أَعُوذُ", "أعوذ", "عوذ"},
	{"114:1", "بِرَبِّ", "برب", "ربب"},
	{"114:1", "ٱلنَّاسِ", "الناس", "نوس"},
	{"114:2", "مَلِكِ", "ملك", "ملك"},
	{"114:2", "ٱلنَّاسِ", "الناس", "نوس"},
	{"114:3", "إِلَـٰهِ", "إله", "أله"},
	{"114:3", "ٱلنَّاسِ", "الناس", "نوس"},
	{"114:4", "مِن", "من", ""},
	{"114:4", "شَرِّ", "شر", "شرر"},
	{"114:4", "ٱلْوَسْوَاسِ", "الوسواس", "وسوس"},
	{"114:4", "ٱلْخَنَّاسِ", "الخناس", "خنس"},
	{"114:5", "ٱلَّذِى", "الذي", ""},
	{"114:5", "يُوَسْوِسُ", "يوسوس", "وسوس"},
	{"114:5", "فِى", "في", ""},
	{"114:5", "صُدُورِ", "صدور", "صدر"},
	{"114:5", "ٱلنَّاسِ", "الناس", "نوس"},
	{"114:6", "مِنَ", "من", ""},
	{"114:6", "ٱلْجِنَّةِ", "الجنة", "جنن"},
	{"114:6", "وَٱلنَّاسِ", "والناس", "نوس"},
	{"96:1", "ٱقْرَأْ", "اقرأ", "قرأ"},
	{"96:1", "بِٱسْمِ", "باسم", "سمو"},
	{"96:1", "رَبِّكَ", "ربك", "ربب"},
	{"96:1", "ٱلَّذِى", "الذي", ""},
	{"96:1", "خَلَقَ", "خلق", "خلق"},
	{"96:2", "خَلَقَ", "خلق", "خلق"},
	{"96:2", "ٱلْإِنسَـٰنَ", "الإنسان", "أنس"},
	{"96:2", "مِنْ", "من", ""},
	{"96:2", "عَلَقٍ", "علق", "علق"},
	{"96:3", "ٱقْرَأْ", "اقرأ", "قرأ"},
	{"96:3", "وَرَبُّكَ", "وربك", "ربب"},
	{"96:3", "ٱلْأَكْرَمُ", "الأكرم", "كرم"},
	{"96:4", "ٱلَّذِى", "الذي", ""},
	{"96:4", "عَلَّمَ", "علم", "علم"},
	{"96:4", "بِٱلْقَلَمِ", "بالقلم", "قلم"},
	{"96:5", "عَلَّمَ", "علم", "علم"},
	{"96:5", "ٱلْإِنسَـٰنَ", "الإنسان", "أنس"},
	{"96:5", "مَا", "ما", ""},
	{"96:5", "لَمْ", "لم", ""},
	{"96:5", "يَعْلَمْ", "يعلم", "علم"},
}

// TestEveryWordOfTheseSurahsResolvesWhetherItIsTypedPlainlyOrPastedFromTheMushaf
// walks the scripture the app opens on. It has failed three ways, and each way
// looked like a corpus gap and was a keying bug:
//
// ٱلْعَـٰلَمِينَ was keyed العلمين, because the dagger alef was dropped rather than also
// spelled out, so the العالمين a reader types reached nothing. مَالِكِ, ٱلصِّرَٰطَ and
// ٱلْإِنسَـٰنَ went the same way.
//
// A word carrying a pause mark was keyed with the mark's space still on it, so no
// input a reader can type reached it at all.
//
// قُلْ, which opens Al-Ikhlas, was a 404 listing قول and قلل and refusing both,
// because normalising invented a collision the authority does not have.
func TestEveryWordOfTheseSurahsResolvesWhetherItIsTypedPlainlyOrPastedFromTheMushaf(t *testing.T) {
	r := quranResolver(t)
	for _, w := range theSurahsAReaderMeetsFirst {
		if w.root == "" {
			continue
		}
		for _, spelling := range []string{w.uthmani, w.ordinary} {
			got, err := r.Resolve(context.Background(), spelling, nil)
			if err != nil {
				t.Errorf("%s %s: the corpus records the root %s for this word and the reader was shown nothing: %v",
					w.ayah, spelling, w.root, err)
				continue
			}
			if got.Root.Letters == w.root {
				continue
			}
			// A spelling several roots share is answered with all of them, and the
			// authority's root has to be among them: a shared answer that drops the
			// right reading is worse than the miss it replaced.
			if slices.ContainsFunc(got.Roots, func(o Root) bool { return o.Letters == w.root }) {
				continue
			}
			t.Errorf("%s %s was served %q where corpus.db records %q",
				w.ayah, spelling, got.Root.Letters, w.root)
		}
	}
}

// TestNoParticleOfTheseSurahsIsHandedARootTheMorphologyDeniesIt guards the other
// half of resolving scripture. هُوَ and لَمْ and مَا have no root in the authority, and
// a ladder that peels letters off a particle until something in the corpus matches
// would teach a reader that the word for "not" comes from a root.
//
// Two of them were worse than peeled. مِنْ was answered منن and عَلَيْهِمْ was answered
// علو, because مَنَّ and عَـٰلِيَهُمْ are spelled that way once the diacritics are gone and
// the corpus shipped only the spellings that have a root — 139 of the 1,492
// rootless forms were answered like that, as method pattern, which the published
// table calls an attested corpus fact. The corpus now ships the rootless spellings
// too. The mushaf's own spelling is unambiguous in the authority and gets the
// authority's answer, that this word has no root; a spelling a rooted word shares
// keeps both readings and says so with Rootless.
func TestNoParticleOfTheseSurahsIsHandedARootTheMorphologyDeniesIt(t *testing.T) {
	r := quranResolver(t)
	for _, w := range theSurahsAReaderMeetsFirst {
		if w.root != "" {
			continue
		}
		got, err := r.Resolve(context.Background(), w.uthmani, nil)
		var miss *NoRootError
		if !errors.As(err, &miss) || !miss.Rootless {
			t.Errorf("%s %s: the morphology writes this spelling with no root, and the caller was answered %v — a root it denies, or a miss it cannot tell from a word we have never seen",
				w.ayah, w.uthmani, answerOf(got, err))
		}

		got, err = r.Resolve(context.Background(), w.ordinary, nil)
		switch {
		case errors.As(err, &miss) && miss.Rootless:
		case err == nil && got.Rootless:
		default:
			t.Errorf("%s %s: the answer %v says nothing about the morphology recording this spelling with no root, so a reader cannot tell the particle they typed from a word that happens to share its letters",
				w.ayah, w.ordinary, answerOf(got, err))
		}
	}
}

// answerOf names what a caller was handed, so a failure reads as the answer the
// reader saw rather than as a Go value.
func answerOf(got Result, err error) string {
	if err != nil {
		return err.Error()
	}
	return fmt.Sprintf("the root %s by %s", got.Root.Letters, got.Method)
}

// TestASpellingAParticleSharesWithARootedWordCarriesBothReadings is the second
// case, and the one no 404 can answer. من typed bare is the particle, which has no
// root, and it is also مَنَّ, "he bestowed", which is منن; عليهم is the particle and
// also عَـٰلِيَهُمْ, which is علو. Serving the root alone hides half the truth and
// missing outright hides the other half, so both are on the table: the roots under
// Roots and the rootless reading under Rootless, with method shared, which claims
// nothing about which reading this is.
func TestASpellingAParticleSharesWithARootedWordCarriesBothReadings(t *testing.T) {
	r := quranResolver(t)
	for _, c := range []struct{ word, root string }{{"من", "منن"}, {"عليهم", "علو"}} {
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err != nil {
			t.Errorf("%s: the corpus attests this spelling under %s and the reader was shown nothing: %v", c.word, c.root, err)
			continue
		}
		if !got.Rootless {
			t.Errorf("%s was served %s alone, and a reader is never told that the word they almost certainly meant has no root",
				c.word, got.Root.Letters)
		}
		if got.Method != MethodShared {
			t.Errorf("%s came back as %s, which the published table calls an attested fact about this spelling, and the corpus does not settle it", c.word, got.Method)
		}
		if !slices.ContainsFunc(got.Roots, func(o Root) bool { return o.Letters == c.root }) {
			t.Errorf("%s lists %v, and the root the corpus does attest for this spelling is not among them", c.word, got.Roots)
		}
	}
}

// TestAWordTheCorpusWritesBothAsANameAndAsAVerbKeepsBothReadings is the case the
// rootless answer must not swallow. يَحْيَىٰ is the name Yahya, which the morphology
// gives no root, and it is also "he lives", which is حيي — and the corpus writes
// the two identically, diacritics and all. An engine that let the rootless record
// settle every spelling it holds would answer the verb with a miss.
func TestAWordTheCorpusWritesBothAsANameAndAsAVerbKeepsBothReadings(t *testing.T) {
	got, err := quranResolver(t).Resolve(context.Background(), "يَحْيَىٰ", nil)
	if err != nil {
		t.Fatalf("the corpus attests this very spelling under حيي and the reader was shown nothing: %v", err)
	}
	if got.Root.Letters != "حيي" || !got.Rootless {
		t.Errorf("يَحْيَىٰ was served %q with rootless=%v, and the corpus writes it as both the name, which has no root, and the verb, which is حيي",
			got.Root.Letters, got.Rootless)
	}
}

func TestAWordTheCorpusWritesWithAPauseMarkIsReachedByTypingTheWord(t *testing.T) {
	// ءَأَسْلَمْتُمْ is written with a pause mark after it, and the corpus spells it no
	// other way. Keyed with the mark's space still attached it was reachable only
	// by a caller who reproduced the space, which no keyboard produces: 2,573 of
	// the 19,805 form rows are written with a space in them.
	r := quranResolver(t)
	for _, spelling := range []string{"ءَأَسْلَمْتُمْ", "ءأسلمتم"} {
		got, err := r.Resolve(context.Background(), spelling, nil)
		if err != nil {
			t.Errorf("%s: %v", spelling, err)
			continue
		}
		if got.Root.Letters != "سلم" {
			t.Errorf("%s was served %q, want سلم", spelling, got.Root.Letters)
		}
	}
}

// TestAWordPastedWithItsRecitationMarkStillOnItReachesTheWord is the resolver's
// half of the pause-mark fix, and it reddens on its own: the builder cleans what it
// ships, and this cleans what arrives. ۩ and ۞ and ۝ are symbols rather than
// combining marks, so the normaliser leaves them standing — a reader who copies
// ٱلْحَمْدُ ۩ out of a mushaf and pastes it whole would key the mark in and reach
// nothing. Drop TrimMarks from key() and this is what goes red.
func TestAWordPastedWithItsRecitationMarkStillOnItReachesTheWord(t *testing.T) {
	r := quranResolver(t)
	for _, pasted := range []string{"ٱلْحَمْدُ ۩", "۞ ٱلْحَمْدُ", "ٱلْحَمْدُ ۝", "الحمد ۩"} {
		got, err := r.Resolve(context.Background(), pasted, nil)
		if err != nil {
			t.Errorf("%s: pasted out of a mushaf with its mark, this reaches nothing: %v", pasted, err)
			continue
		}
		if got.Root.Letters != "حمد" {
			t.Errorf("%s was served %q, want حمد", pasted, got.Root.Letters)
		}
	}
}

// TestNoSpellingRecordedAsRootlessIsAnsweredARootWithNothingToSaySo is the whole
// class rather than the handful the surahs above happen to hold. 139 of the 1,492
// rootless form rows used to come back with a root and `method: "pattern"`, which
// the published table calls an attested corpus fact about the spelling sent: مِنْ was
// منن, عَلَيْهِمْ was علو. Every spelling the corpus records with no root must now come
// back either as the authority's answer — this word has none — or, where a rooted
// word shares it, as a shared answer carrying Rootless beside the roots. A root with
// nothing beside it is the bug, whatever the count is on the day.
func TestNoSpellingRecordedAsRootlessIsAnsweredARootWithNothingToSaySo(t *testing.T) {
	f, err := os.Open(filepath.Join(testdataDir, "quran.json"))
	if err != nil {
		t.Fatalf("open the Qur'anic corpus: %v", err)
	}
	defer f.Close()
	var c Corpus
	if err := json.NewDecoder(f).Decode(&c); err != nil {
		t.Fatalf("read the Qur'anic corpus: %v", err)
	}
	r := New(NewMemoryStore(c))

	var unmarked []string
	for _, spelling := range c.Rootless {
		got, err := r.Resolve(context.Background(), spelling, nil)
		var miss *NoRootError
		if errors.As(err, &miss) && miss.Rootless {
			continue
		}
		if err == nil && got.Rootless {
			continue
		}
		unmarked = append(unmarked, fmt.Sprintf("%s → %s", spelling, answerOf(got, err)))
	}
	if len(unmarked) > 0 {
		t.Errorf("%d of the %d spellings the morphology records with no root are answered with something other than that fact — a root it denies, or a miss no caller can tell from a word we have never seen: %v",
			len(unmarked), len(c.Rootless), unmarked[:min(len(unmarked), 8)])
	}
}
