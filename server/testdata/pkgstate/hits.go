// Package pkgstate is TestPackageState's control: one package var, which pkgstate must refuse.
package pkgstate

var hits int

func Hit() int { hits++; return hits }
