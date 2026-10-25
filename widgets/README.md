# widgets/

Rutile's widget system (plan items 4.1 to 4.5).

- `spec.schema.json`: the widget spec v1 as JSON Schema 2020-12. A widget is `{"version": 1, "name", "root"}`
  where `root` is a node tree (`row`, `column`, `grid`, `card`, `header`, `tile`, `heroImage`, `stat`,
  `progress`, `listRow`, `chip`). Text may hold bindings `{{source.field}}`; never code.
- `examples/`: example widgets. `templates/` (to come): the Custom widgets app's templates.

Check everything with `python3 tools/widget_check.py` (standard library only); `tests/test_widget_spec.py`
runs it in `make check`.

The local-model line may own this directory for a task (see `docs/sidework.md` and `tools/ownership.json`):
while a `local/*` branch is open here, the main line does not edit it, so merges cannot conflict.
