# Gate — `scripts/qa.sh`

- Exit code = verdict. Writes `qa-report.json`. Merge on exit code, never opinion.
- Checks by number: 1 Go build/vet/test · 2 Flutter suite + no golden refresh · 3 e2e journeys · 4-6 judgments (recorded) · 7 toolchain record (`docs/toolchain.md` brew-leaves) + corpus size budget. Every entry carries gate number; missing gate = fail.
- Red test never deleted in gate it reddens. Dead-test deletion = separate later commit naming violation.
- Goldens never refreshed inside gate. Moved golden → open old + new PNG, say what changed + why right.
- Marker `TO`+`DO` needs `(#issue)`; `git grep --untracked` → new untracked files count.
- `brew install` for Wird → add line to `docs/toolchain.md` brew-leaves block same commit.
- Visual rule (every gate): render at 402x874 (tablet 1194x834 separately), look, compare vs design, check Arabic by eye, verdict in reader's words. Full: `docs/guides/gate-visual.md`.
- Disk error in tests → `du -sh $TMPDIR` first.
