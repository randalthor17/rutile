# Task: widget-schema

## Goal
Write the JSON Schema for Rutile's widget spec v1, so a small local or cloud LLM can produce widgets as
JSON and the shell can validate them. Plan item 4.1.

## Files you may touch
- `widgets/spec.schema.json`
- `widgets/examples/*.json`

## What the schema describes
A widget is a JSON object `{ "version": 1, "name": string, "root": <node> }`. A node has a `type` and
type-specific fields. Types (all lowercase):

- layout: `row`, `column`, `grid` (`children`, `spacing`, `columns` for grid)
- `card` (a surface; `tone` is a surface role name, `children`)
- `header` (`icon`, `title`)
- `tile` (a tinted block; `tone`, `children`)
- `heroImage` (`source`, `aspect`)
- `stat` (`label`, `value`, `unit`)
- `progress` (`value` 0..1, `style`: `linear` or `wavy`)
- `listRow` (`icon`, `title`, `subtitle`, `trailingIcon`)
- `chip` (`label`, `icon`)

Text fields may contain bindings written `{{source.field}}` (for example `{{weather.temperature}}`).
They must not contain code. Allowed data sources: `clock`, `weather`, `calendar`, `battery`, `system`,
`countdown`, `http`, `files`.

Use the real design vocabulary: `tone` values are Rutile color role names written in snake_case
(`surface_container`, `primary_container`, ...; read `theme/roles.json` for the full list), and icon
names are Material Symbols ligature names.

## Acceptance
- `python3 -m json.tool widgets/spec.schema.json` succeeds and the file declares
  `"$schema": "https://json-schema.org/draft/2020-12/schema"`.
- Every example in `widgets/examples/` (write at least four, covering weather, a countdown, a list and a
  stat card) is valid JSON and uses only node types and fields the schema defines.
- `tone` is restricted with an `enum` taken from `theme/roles.json`, not free text.
- Unknown fields are rejected (`"additionalProperties": false` on every node).

## Out of scope
A validator program, QML, anything outside the paths above. Claude will add the validator and tests.
