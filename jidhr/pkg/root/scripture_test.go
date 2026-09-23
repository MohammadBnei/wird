package root

import (
	"context"
	"errors"
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

// theOpeningTheSincerityAndTheClot is every word of Al-Fatiha, of Al-Ikhlas, and
// of the first five ayat of Al-Alaq: the surahs a reader meets first, in every
// prayer and on the first screen of the app. The Uthmani column and the roots are
// read out of corpus.db; the ordinary column is what a person types.
var theOpeningTheSincerityAndTheClot = []scriptureWord{
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
	for _, w := range theOpeningTheSincerityAndTheClot {
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

// TestNoParticleOfTheseSurahsIsHandedARootPeeledOutOfIt guards the other half of
// resolving scripture. هُوَ and لَمْ and مَا have no root in the authority, and a
// ladder that peels letters off a particle until something in the corpus matches
// would teach a reader that the word for "not" comes from a root.
//
// Two of these do come back with a root, and it is not peeling that does it: the
// corpus spells مَنَّ, "he bestowed", and عَـٰلِيَهُمْ of 76:21 the same way مِنْ and
// عَلَيْهِمْ are spelled once the diacritics are gone, and the spelling it attests is
// the only one it ships. The authority records مِنْ itself with no root, so the
// answer contradicts it. Fixing that means shipping the 1,492 forms the morphology
// gives no root to, so that a spelling the corpus records rootless is a miss
// before any other reading of the same letters is offered. Until then the guard
// here is the narrower one it can honestly make.
func TestNoParticleOfTheseSurahsIsHandedARootPeeledOutOfIt(t *testing.T) {
	r := quranResolver(t)
	for _, w := range theOpeningTheSincerityAndTheClot {
		if w.root != "" {
			continue
		}
		for _, spelling := range []string{w.uthmani, w.ordinary} {
			got, err := r.Resolve(context.Background(), spelling, nil)
			if errors.Is(err, ErrNoRoot) {
				continue
			}
			if err != nil {
				t.Errorf("%s %s: want a miss, got %v", w.ayah, spelling, err)
				continue
			}
			if got.Method == MethodStripped {
				t.Errorf("%s %s was served the root %q by peeling it down to a stem that happened to match, and the morphology records no root for this word at all",
					w.ayah, spelling, got.Root.Letters)
			}
		}
	}
}

func TestAWordTheCorpusWritesWithAPauseMarkIsReachedByTypingTheWord(t *testing.T) {
	// ءَأَسْلَمْتُمْ is written with a pause mark after it, and the corpus spells it no
	// other way. Keyed with the mark's space still attached it was reachable only
	// by a caller who reproduced the space, which no keyboard produces: 682 words
	// were reachable by nothing a person can type.
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
