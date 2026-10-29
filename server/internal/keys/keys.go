// Package keys is wird's error key registry, the only file that may make one
// (docs/adr/0038). A client branches on a key; the message beside it is for a
// person and may change. errkeys_test.go runs ukubi-go's errkeys analyzer
// against this file, so a key written anywhere else fails the build's tests.
//
// A 500 answers with errs.KeyInternal, ukubi-go's own: what went wrong is in
// the log, not the key.
package keys

import "github.com/MohammadBnei/ukubi-go/errs"

// The bearer token.
const (
	TokenMissing  errs.Key = "auth.token_missing"
	TokenRejected errs.Key = "auth.token_rejected"
)

// A request the client has to change before sending again.
const (
	BadBatch    errs.Key = "request.bad_batch"
	BatchTooBig errs.Key = "request.batch_too_big"
	BadCursor   errs.Key = "request.bad_cursor"
	BadKind     errs.Key = "request.bad_kind"
	BadRoot     errs.Key = "request.bad_root"
	BadAyah     errs.Key = "request.bad_ayah"
)

// NotFound: the store has nothing under what was asked for.
const NotFound errs.Key = "store.not_found"

// The recogniser and the Android build, both served from object storage.
const (
	ModelsNotPublished errs.Key = "models.not_published"
	ModelsUnreachable  errs.Key = "models.unreachable"
	APKNotPublished    errs.Key = "apk.not_published"
	APKUnreachable     errs.Key = "apk.unreachable"
)

// One /v1/sync op's verdict, beside its reason. op.retry is the only one a
// device should send again.
const (
	OpUnknownKind errs.Key = "op.unknown_kind"
	OpBadBody     errs.Key = "op.bad_body"
	OpBadValue    errs.Key = "op.bad_value"
	OpNotFound    errs.Key = "op.not_found"
	OpConflict    errs.Key = "op.conflict"
	OpRetry       errs.Key = "op.retry"
)
