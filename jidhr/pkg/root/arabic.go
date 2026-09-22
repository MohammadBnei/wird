package root

// ContainsArabicLetter reports whether s holds at least one Arabic letter. It is
// exported because it is the boundary between 400 and 404, and rootd has to ask
// the question the resolver asks: a second copy of the rule in the HTTP layer can
// drift, and a caller would then be told its word is not Arabic by one half of
// jidhr and resolved by the other.
func ContainsArabicLetter(s string) bool { return containsArabicLetter(s) }
