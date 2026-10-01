package api

import (
	"log/slog"
	"net/http"
	"time"
)

// Where the public site's Download buttons point.
//
// Open, like /models/, and for the same reason: whoever wants the app has no
// account yet. It is the same move as well — a presigned GET and a 302, so
// 40 MB never passes through a pod sized for JSON.
//
// The key comes from WIRD_APK_KEY rather than a fixed name, and the name it
// holds carries the build's digest (android/wird-<sha256>.apk), for the reason
// ADR 0008 gives for the recogniser: a key that is reused is a key a resumed
// download can land on halfway through a different build. Publishing a release
// is uploading a new object and pointing WIRD_APK_KEY at it; the old object
// keeps answering whoever started on it.
const apkPath = "GET /download/android"

func apk(store *modelStore, key string, log *slog.Logger) http.HandlerFunc {
	if store == nil || key == "" {
		// 503, not 404: the page is right to offer the app, it is the
		// deployment that has not published one yet.
		return func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "no Android build is published here yet", http.StatusServiceUnavailable)
		}
	}
	return func(w http.ResponseWriter, r *http.Request) {
		signed, err := store.sign.get(store.bucket, key, time.Now(), modelURLTTL)
		if err != nil {
			log.Error("presign the apk", "key", key, "err", err)
			http.Error(w, "the Android build cannot be reached", http.StatusBadGateway)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		http.Redirect(w, r, signed, http.StatusFound)
	}
}
