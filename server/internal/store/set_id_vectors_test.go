package store_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/store"
)

// vectorsPath is the one file both halves answer to. The device suite reads
// the same rows from app/test/data/set_id_vectors_test.dart; neither suite
// computes what it asserts, so the two cannot agree with themselves while
// disagreeing with each other.
const vectorsPath = "../../../docs/adr/0002-set-identity-vectors.json"

type setIDVector struct {
	Label         string `json:"label"`
	ReadingOrder  string `json:"reading_order"`
	StartAyahID   int    `json:"start_ayah_id"`
	EndAyahID     int    `json:"end_ayah_id"`
	ExpectedSetID string `json:"expected_set_id"`
}

func setIDVectors(t *testing.T) []setIDVector {
	t.Helper()
	raw, err := os.ReadFile(vectorsPath)
	if err != nil {
		t.Fatalf("the shared set id vectors are unreadable, so nothing checks the server against the device: %v", err)
	}
	var file struct {
		Vectors []setIDVector `json:"vectors"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatalf("%s is not readable as vectors: %v", filepath.Base(vectorsPath), err)
	}
	if len(file.Vectors) == 0 {
		t.Fatal("the shared vectors are empty, so this test passes without checking anything")
	}
	return file.Vectors
}

// The failure: the server names a set by an id no device derives, so every
// prayer a real reader sends is refused — permanently, which dead-letters it —
// and the prayer is lost. The expectations here are checked in, not computed,
// so this test reddens the moment the server's derivation drifts from the one
// the device and the ADR publish.
func TestTheServerDerivesTheSetIdEveryDeviceDerivesForTheSameRange(t *testing.T) {
	for _, v := range setIDVectors(t) {
		if got := store.SetID(v.ReadingOrder, v.StartAyahID, v.EndAyahID); got != v.ExpectedSetID {
			t.Errorf("%s (%s %d-%d): the server calls it %s, every other implementation calls it %s",
				v.Label, v.ReadingOrder, v.StartAyahID, v.EndAyahID, got, v.ExpectedSetID)
		}
	}
}
