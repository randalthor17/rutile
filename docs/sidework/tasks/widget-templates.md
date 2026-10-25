# Task: widget-templates

Depends on: `widget-schema` merged first.

## Goal
Write the template widgets shown in the Custom widgets app, as valid spec JSON. Plan item 4.5.

## Files you may touch
- `widgets/templates/*.json`

## Content
Six categories with five templates each, the way the Googlebook "Custom widgets" app lists them:
`weather`, `daily-update`, `world-clock`, `finance`, `countdown`, `sports`. File names are
`<category>-<n>.json` (`weather-1.json` ... `sports-5.json`), 30 files. Each has a distinct layout and
uses a different mix of node types and tones, not five copies of one design.

## Acceptance
Run this after every change; a commit is refused until it passes:

```
python3 tools/widget_check.py --templates
```

It checks that:
- there are 30 files, all valid JSON, all matching `widgets/spec.schema.json`;
- no two templates have the same `root` structure;
- each template uses at least one binding from an allowed data source.

## Out of scope
Changing the schema. If it cannot express something, list it in your summary instead.
