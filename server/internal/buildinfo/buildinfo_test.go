package buildinfo

import "testing"

// The committed file must stay "dev": a real version committed here would be
// what every local and test build claims to be. Only the image build writes
// one (Dockerfile). Mutation: commit "0.1.0" in version.txt and this fails.
func TestALocalBuildDoesNotClaimARelease(t *testing.T) {
	if got := Version(); got != "dev" {
		t.Errorf("Version() = %q, want \"dev\" (the image build writes the real one)", got)
	}
	// Positive control: the embed is trimmed, not read raw.
	if version == Version() {
		t.Errorf("version.txt has no trailing newline to trim, so TrimSpace is untested: %q", version)
	}
}
