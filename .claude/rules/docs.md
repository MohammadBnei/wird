---
paths:
  - "docs/**"
  - "README.md"
  - "CONTRIBUTING.md"
---
# Human docs — style guide

Reader: new contributor, curious outsider, future maintainer. English only. Light prose: short sentences, plain words, no caveman, no marketing.

## Layout
```
docs/README.md          L0 — what Wird is, glossary, context diagram, page map, tours
docs/tours/             narration: one journey end to end, links into architecture pages
docs/architecture/      L1 container pages → L2 component pages (subdir per container)
docs/guides/            how-to (run, test, wire auth, visual gate)
docs/adr/               decisions (caveman lite, own template)
docs/research/          investigations, frozen
docs/journal/           field walks, frozen, not kept current
docs/design/            vendored, never hand-edit
```

## Architecture page template (L1 + L2)
```md
# <Component>
> <one line: what it is>. Level L1|L2 · Parent [X](../x.md) · Children [A](a.md), [B](b.md)

## Black box
2-4 sentences: purpose, who calls it.
| In | Out | Depends on |
mermaid: outside view (sequenceDiagram / flowchart of neighbours)

## White box
mermaid: internals (flowchart / stateDiagram-v2 / erDiagram / classDiagram)
### 1. <step>
short prose · excerpt ≤ 15 lines · [file.dart:139](../../../app/lib/data/file.dart#L139)

## Why it is this way
- [ADR NNNN](../adr/NNNN-….md) — one line

## Go deeper
children / related / tours passing here
```

## Rules
- ≥ 1 mermaid in Black box + ≥ 1 in White box. Diagrams before prose.
- Black box never names internals (no private functions, no table columns). Reader can stop there.
- Behaviour claim → `path#Lnn` link to code. `#Lnn` only on code files; `.md` targets → heading anchor.
- Links relative. Never absolute GitHub URLs to this repo.
- Code excerpt ≤ 15 lines, copied verbatim, language tag set.
- Glossary terms (`docs/README.md`) used exactly; never synonym-rotate.
- No hostnames except `wird.bnei.dev`. No secret names, emails, personal names.
- Placeholder in unfinished page: `> pending`. Never `TO`+`DO` marker.
- Tours: second person, 2-4 sentences per stop, each stop links to page anchor. Tours never duplicate page content; pages never depend on tours.
