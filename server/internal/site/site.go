// Package site is the public page at wird.bnei.dev: what Wird is, two live
// demos, and the Android download. README.md beside this file says where each
// file under static/ comes from and which of them are ours to edit.
package site

import (
	"embed"
	"io/fs"
	"net/http"
)

// all: because the design system's files live under _ds/, and a plain embed
// silently leaves out every path that starts with an underscore.
//
//go:embed all:static
var static embed.FS

// Handler serves static/. Embedded files carry no modification time, so
// nothing tells a cache a file changed: no-cache makes Cloudflare and the
// browser revalidate instead of pairing a new page with an old script.
func Handler() http.Handler {
	sub, err := fs.Sub(static, "static")
	if err != nil {
		panic(err) // the directive above guarantees static/ exists
	}
	files := http.FileServerFS(sub)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache")
		files.ServeHTTP(w, r)
	})
}
