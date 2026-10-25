# Task: llm-docs

## Goal
Write reference documents an LLM can read in one go to write correct Rutile QML and widget JSON. Plan
item 4.8, first part.

## Files you may touch
- `docs/llm/TOKENS.md`
- `docs/llm/COMPONENTS.md`

## Content
`TOKENS.md`: every singleton in `shell/common/` (`Colors`, `Shapes`, `Elevation`, `Motion`, `Type`,
`Fonts`, `Spacing`) with the exact property names and what they are for, plus 6 short QML usage
examples. Include the rule that `on_primary` is written `Colors.primaryOn` and why.

`COMPONENTS.md`: every component in `shell/components/` with its properties, allowed values (button
types and sizes, shapes, width variants), signals, and one example each.

Facts come only from the source files, `tokens/*.json` and `docs/components.md`. If something is not
there, leave it out.

## Acceptance
Run this after every change; a commit is refused until it passes:

```
python3 tools/llm_docs_check.py
```

It checks that:
- Every property of every singleton in `shell/common/` that is generated (`Shapes`, `Elevation`,
  `Motion`, `Type`, `Fonts`, `Colors`) appears in `TOKENS.md` by exact name, grouped, not listed as
  prose. A table per singleton is fine.
- Every component's public properties appear in `COMPONENTS.md`.
- Each QML example only uses names that exist in the source.
- No hex colors, numeric radii or numeric durations appear in the QML examples.

## Out of scope
Editing any QML, generators, tests or `tools/llm_docs_check.py` (it is Claude's).
