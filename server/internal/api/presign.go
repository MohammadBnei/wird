package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Signature Version 4, the presigned-GET case only.
//
// Written here rather than taken from a dependency because this server has
// five direct requirements and the SDK that does this brings a dozen modules
// to answer one question. Presigning a GET is also the simplest shape SigV4
// has: nothing is signed but the query and the host, and the payload hash is
// the literal UNSIGNED-PAYLOAD rather than a digest of anything.
//
// A wrong signature is a 403 from the store, which is loud. The thing to be
// careful of is not the algorithm but the inputs: an expiry longer than the
// reader needs, or a key that reaches more than one bucket.
//
// Held to Amazon's own published example, which is the only way to know this
// is right without a live store — see presign_test.go.
type presigner struct {
	endpoint  string // https://s3.bnei.dev
	region    string // garage, and it is not cosmetic
	accessKey string
	secret    string
}

// get signs a GET for bucket/key, valid for ttl.
//
// Path-style — https://s3.bnei.dev/<bucket>/<key> — never
// <bucket>.s3.bnei.dev. The route's certificate is issued for the one
// hostname, so a bucket-vhost URL lands on a name nothing has a cert for and
// fails as a TLS error that reads like a network problem.
func (p presigner) get(bucket, key string, now time.Time, ttl time.Duration) (string, error) {
	base, err := url.Parse(p.endpoint)
	if err != nil {
		return "", err
	}
	stamp := now.UTC().Format("20060102T150405Z")
	day := stamp[:8]
	scope := strings.Join([]string{day, p.region, "s3", "aws4_request"}, "/")

	// Each path segment is escaped on its own: a key may hold slashes, and
	// they are separators rather than characters to encode.
	var path strings.Builder
	if bucket != "" {
		path.WriteString("/" + bucket)
	}
	for segment := range strings.SplitSeq(key, "/") {
		path.WriteString("/" + awsEscape(segment))
	}

	query := url.Values{
		"X-Amz-Algorithm":     {"AWS4-HMAC-SHA256"},
		"X-Amz-Credential":    {p.accessKey + "/" + scope},
		"X-Amz-Date":          {stamp},
		"X-Amz-Expires":       {strconv.Itoa(int(ttl.Seconds()))},
		"X-Amz-SignedHeaders": {"host"},
	}

	canonical := strings.Join([]string{
		"GET",
		path.String(),
		canonicalQuery(query),
		"host:" + base.Host + "\n",
		"host",
		"UNSIGNED-PAYLOAD",
	}, "\n")

	toSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		stamp,
		scope,
		sha256hex(canonical),
	}, "\n")

	key4 := hmacOf([]byte("AWS4"+p.secret), day)
	key4 = hmacOf(key4, p.region)
	key4 = hmacOf(key4, "s3")
	key4 = hmacOf(key4, "aws4_request")
	query.Set("X-Amz-Signature", hex.EncodeToString(hmacOf(key4, toSign)))

	return base.Scheme + "://" + base.Host + path.String() + "?" + canonicalQuery(query), nil
}

// canonicalQuery sorts by key and escapes both halves the way the signature
// expects. url.Values.Encode() sorts the same way but escapes a space as `+`,
// which SigV4 does not accept.
func canonicalQuery(v url.Values) string {
	keys := make([]string, 0, len(v))
	for k := range v {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	pairs := make([]string, 0, len(keys))
	for _, k := range keys {
		pairs = append(pairs, awsEscape(k)+"="+awsEscape(v.Get(k)))
	}
	return strings.Join(pairs, "&")
}

// awsEscape is RFC 3986 unreserved, which is url.QueryEscape with `+` for a
// space corrected to %20 and `~` left alone.
func awsEscape(s string) string {
	e := url.QueryEscape(s)
	e = strings.ReplaceAll(e, "+", "%20")
	return strings.ReplaceAll(e, "%7E", "~")
}

func sha256hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func hmacOf(key []byte, data string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(data))
	return mac.Sum(nil)
}
