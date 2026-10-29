package lane

import "testing"

// Every hamza seat and alef maqsura must fold the same on both sides of the
// join, or a hamza root finds no article in Lane.
func TestAHamzaSeatOrAlefMaqsuraMissesItsLaneArticle(t *testing.T) {
	if got, want := Fold("اإآؤئءأىيب"), "أأأأأأأييب"; got != want {
		t.Fatalf("Fold gave %q, want %q", got, want)
	}
}
