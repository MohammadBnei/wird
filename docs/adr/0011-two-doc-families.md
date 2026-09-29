# 11. Agent docs and human docs are two families with two styles

Date: 2026-09-29. Status: accepted.

## Context

The repo had no agent instructions. The architecture spec and the traps agents
kept hitting lived outside the repo, so a fresh clone could not explain itself.
`docs/` mixed decisions, field logs, research, standing rules and a vendored
design drop in one flat folder. Diagrams were ASCII. The README had drifted:
it still said the senses were bundled after ADR 0010 moved them to the server.

Two readers want different things. A coding agent wants dense facts it can load
cheaply on every session. A person new to Wird wants to start at "what is this"
and zoom in only as far as they need.

## Decision

- **Agent family:** `CLAUDE.md` and `.claude/**` (rules scoped by path, a
  distilled spec, handoffs). Written in caveman ultra: fragments, no articles,
  exact identifiers. The rule is stated in `CLAUDE.md`.
- **Human family:** `docs/**`, `README.md`, `CONTRIBUTING.md`. Light English
  prose, mermaid diagrams first. Architecture pages are layered in three
  levels (overview, container, component). Each page has a black-box half
  (contract and outside view) and a white-box half (internals, code excerpts,
  `path#Lnn` links).
- **Tours** in `docs/tours/` narrate one journey end to end and link into the
  pages. The pages never depend on them.
- **ADRs** stay in `docs/adr/`. Existing ones are untouched. New ones use
  caveman lite: full, short sentences a newcomer can follow.
- `docs/` is split by type: `architecture/`, `tours/`, `guides/`, `adr/`,
  `research/`, `journal/`, `design/`.
- A `docs.yml` workflow checks links, line anchors and mermaid syntax on every
  PR. `CLAUDE.md` requires the matching page to change in the same PR as the
  behaviour.

## Alternatives

- **One family for everyone.** Agents pay for prose on every load; humans cannot
  read caveman. Rejected.
- **A static site generator.** Search and navigation, but a build to maintain.
  GitHub already renders markdown and mermaid. Rejected for now.
- **Path and symbol references instead of line links.** They rot less, but a line
  link lands the reader on the exact code. Chosen: line links, with CI flagging
  docs that link into files a PR changes.

## Consequences

- Line links drift when code moves. The workflow can only warn, not prove them
  wrong, so authors must recheck flagged links.
- Moving a doc means updating code comments that cite it. Some paths are
  load-bearing for tests and the gate; `CLAUDE.md` lists them.
- Two styles to keep apart. The docs rule is scoped to human paths only.

## Reversibility

Cheap. The files are plain markdown. Merging the families back is a rewrite of
`CLAUDE.md` and `.claude/`, not of the human pages.
