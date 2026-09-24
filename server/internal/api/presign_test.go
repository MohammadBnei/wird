package api

import (
	"net/url"
	"strings"
	"testing"
	"time"
)

// Amazon's own worked example for a presigned GET, from the SigV4
// documentation: the `test` bucket's `test.txt`, 86400 seconds, the
// credentials every AWS signing example uses. It is published with the
// signature it must produce, which is the only way to know this
// implementation is right without a store to ask.
//
// A wrong signature is a 403 that reads like a permissions problem, and the
// store is somebody else's to look at. Getting it wrong here would be
// debugged in the wrong repository.
func TestTheSignatureIsWrongAndTheStoreAnswers403(t *testing.T) {
	p := presigner{
		endpoint:  "https://examplebucket.s3.amazonaws.com",
		region:    "us-east-1",
		accessKey: "AKIAIOSFODNN7EXAMPLE",
		secret:    "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
	}
	// The example signs a virtual-host URL, so the "bucket" is empty and the
	// key carries the object: what is being pinned is the algorithm, not our
	// path-style choice.
	got, err := p.get("", "test.txt",
		time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC), 86400*time.Second)
	if err != nil {
		t.Fatal(err)
	}

	const want = "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
	q, err := url.Parse(got)
	if err != nil {
		t.Fatal(err)
	}
	if sig := q.Query().Get("X-Amz-Signature"); sig != want {
		t.Errorf("signature is %s\nAmazon's worked example says %s", sig, want)
	}
}

// Garage is reached path-style because the route's certificate is issued for
// the one hostname. A bucket-vhost URL lands on a name nothing has a cert
// for, and the failure is a TLS error that reads like the network.
func TestTheUrlIsAddressedToAHostNothingHasACertificateFor(t *testing.T) {
	p := presigner{
		endpoint:  "https://s3.bnei.dev",
		region:    "garage",
		accessKey: "GK1234",
		secret:    "secret",
	}
	got, err := p.get("wird-models", "base-ar-quran/38853d7df20b/quran-tokens.txt",
		time.Now(), 15*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, "https://s3.bnei.dev/wird-models/base-ar-quran/") {
		t.Errorf("not path-style: %s", got)
	}
	if strings.Contains(got, "wird-models.s3.bnei.dev") {
		t.Error("addressed to a bucket subdomain")
	}
}

// A key holds slashes and they are separators. Escaping them turns one object
// into a name no store has.
func TestTheSlashesInAKeyAreEscapedIntoOneLongName(t *testing.T) {
	p := presigner{endpoint: "https://s3.bnei.dev", region: "garage", accessKey: "k", secret: "s"}
	got, _ := p.get("b", "one/two/three.onnx", time.Now(), time.Minute)
	// The path only: X-Amz-Credential carries slashes of its own and those are
	// escaped correctly.
	path, _, _ := strings.Cut(got, "?")
	if strings.Contains(path, "%2F") {
		t.Errorf("a separator was encoded: %s", path)
	}
	if !strings.Contains(got, "/b/one/two/three.onnx?") {
		t.Errorf("the key did not survive: %s", got)
	}
}

// SigV4 wants %20, and url.Values.Encode writes `+`. A signature computed
// over one and presented with the other is refused.
func TestASpaceIsSignedOneWayAndSentAnother(t *testing.T) {
	if got := awsEscape("a b"); got != "a%20b" {
		t.Errorf("escaped as %q", got)
	}
	if got := awsEscape("~"); got != "~" {
		t.Errorf("tilde escaped as %q, and RFC 3986 leaves it alone", got)
	}
}
