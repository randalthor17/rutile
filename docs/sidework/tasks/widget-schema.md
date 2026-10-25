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

## How to structure it
Nodes nest to any depth (a card holds a column that holds a row that holds stats), so the schema must be
recursive. Do not copy node definitions into each level. Instead:

- one entry in `$defs` per node type, each with `"properties": {"type": {"const": "<type>"}}`, its own
  fields, `"required"` and `"additionalProperties": false`;
- a `$defs` entry `node` that is a `oneOf` of `{"$ref": "#/$defs/<type>"}` for all eleven types;
- `children` everywhere is `{"type": "array", "items": {"$ref": "#/$defs/node"}}`, and `root` is
  `{"$ref": "#/$defs/node"}`;
- shared pieces (`tone`, a binding-capable text field) are `$defs` entries too, referenced with `$ref`.

## Acceptance
Run this after every change; a commit is refused until it passes. It is the whole acceptance test, it
needs nothing installed, and it prints one line per problem with the JSON path:

```
python3 tools/widget_check.py
```

It checks that:
- `widgets/spec.schema.json` is valid JSON and declares `"$schema": "https://json-schema.org/draft/2020-12/schema"`;
- every node type above has its subschema, with `"additionalProperties": false` (unknown fields rejected);
- `tone` is restricted with an `enum` of names from `theme/roles.json`, not free text;
- every example in `widgets/examples/` (write at least four, covering weather, a countdown, a list and a
  stat card) matches the schema, and every binding uses an allowed source.

The checker supports a subset of JSON Schema and names any keyword it does not support; use the ones it
lists. If it reports the same problem twice after you changed something, re-read this brief and the
error before trying again.

## Out of scope
Changing `tools/widget_check.py` (it is Claude's), QML, anything outside the paths above.
