"""The real widget spec on main: widgets/spec.schema.json and widgets/examples/ (plan item 4.1)."""
import io
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import widget_check as wc  # noqa: E402

SCHEMA = json.loads((ROOT / "widgets" / "spec.schema.json").read_text())
ROLES = json.loads((ROOT / "theme" / "roles.json").read_text())["roles"]


def widget(root):
    return {"version": 1, "name": "t", "root": root}


def problems(w):
    return wc.validate(w, SCHEMA, SCHEMA) + wc.binding_problems(w)


class RealSpec(unittest.TestCase):
    def test_the_acceptance_check_passes_on_main(self):
        out = io.StringIO()
        self.assertEqual(wc.main([], out=out), 0, out.getvalue())

    def test_the_templates_pass_their_check(self):
        # the Widgets app's templates (plan 4.5, D82, D87): written on main now, not by the local model
        out = io.StringIO()
        self.assertEqual(wc.main(["--templates"], out=out), 0, out.getvalue())

    def test_nodes_nest_to_any_depth(self):
        # The first draft only described two levels.
        w = widget({"type": "card", "tone": "surface_container", "children": [{"type": "column", "children": [
            {"type": "row", "spacing": "sm", "children": [{"type": "tile", "tone": "primary_container", "children": [
                {"type": "stat", "value": "{{system.cpu}}", "unit": "%"}]}]}]}]})
        self.assertEqual(problems(w), [])

    def test_tones_are_surface_roles_only(self):
        tones = SCHEMA["$defs"]["tone"]["enum"]
        self.assertTrue(set(tones) <= set(ROLES))
        self.assertIn("surface_container", tones)
        self.assertFalse([t for t in tones if t.startswith("on_")], "on_* roles are content colors, not surfaces")

    def test_what_the_spec_refuses(self):
        chip = {"type": "chip", "label": "x"}
        cases = {
            "unknown field": {"type": "chip", "label": "x", "colour": "red"},
            "content color as tone": {"type": "card", "tone": "on_primary", "children": [chip]},
            "progress above 1": {"type": "progress", "value": 1.5},
            "code in a binding": {"type": "progress", "value": "{{countdown.left}} + 1"},
            "empty children": {"type": "column", "children": []},
            "grid without columns": {"type": "grid", "children": [chip]},
            "unknown node type": {"type": "slider"},
            "aspect not w:h": {"type": "heroImage", "source": "a.png", "aspect": "wide"},
            "icon not a ligature name": {"type": "header", "title": "x", "icon": "Bad Icon"},
            "unknown field three levels down": {"type": "column", "children": [
                {"type": "row", "children": [{"type": "stat", "value": "1", "x": 1}]}]},
            "binding to an unknown source": {"type": "chip", "label": "{{todo.title}}"},
        }
        for name, root in cases.items():
            self.assertTrue(problems(widget(root)), name)


class Sources(unittest.TestCase):
    """widgets/sources.json (plan 4.2): bindings name a source's real fields, and a source that needs options has
    them in the widget's `sources`."""
    def test_catalog_and_schema_agree(self):
        catalog = json.loads((ROOT / "widgets" / "sources.json").read_text())["sources"]
        options = SCHEMA["$defs"]["sources"]["properties"]
        self.assertTrue(set(options) <= set(catalog), set(options) - set(catalog))
        for name, entry in catalog.items():
            self.assertTrue(entry["description"], name)
            for field, f in entry["fields"].items():
                self.assertIn(f["type"], ("text", "number", "fraction", "boolean", "numbers", "list", "open"), f"{name}.{field}")
                self.assertTrue(f["description"], f"{name}.{field}")
                if f["type"] == "list":
                    self.assertTrue(f["item"], f"{name}.{field}")

    def test_bindings_against_the_catalog(self):
        def chip(label, **extra):
            return dict(widget({"type": "chip", "label": label}), **extra)
        good = {
            "a field": chip("{{battery.level}}%"),
            "a list's item field": chip("{{calendar.events.title}}", sources={"calendar": {"path": "~/cal"}}),
            "a whole list": chip("{{files.lines}}", sources={"files": {"path": "/tmp/x"}}),
            "below an open field": chip("{{files.json.a.b}}", sources={"files": {"path": "/tmp/x"}}),
            "anything under http": chip("{{http.rates.EUR}}", sources={"http": {"url": "https://example.org/x"}}),
        }
        for name, w in good.items():
            self.assertEqual(problems(w), [], name)
        bad = {
            "an unknown field": (chip("{{battery.lvl}}"), "battery has no field 'lvl'"),
            "below a plain field": (chip("{{battery.level.x}}"), "is a number, with no fields below it"),
            "a list's unknown item field": (chip("{{calendar.events.place}}", sources={"calendar": {"path": "/c"}}),
                                            "bind one of its items' fields: title"),
            "an open field itself": (chip("{{files.json}}", sources={"files": {"path": "/x"}}), "is a document"),
            "options missing": (chip("{{countdown.text}}"), "gives no sources.countdown with target"),
        }
        for name, (w, said) in bad.items():
            found = " | ".join(m for _, m in problems(w))
            self.assertIn(said, found, name)
        refused = {
            "an option the source has not": {"clock": {"zone": "x"}},
            "a countdown target not a date": {"countdown": {"target": "Christmas"}},
            "http not http": {"http": {"url": "file:///etc/passwd"}},
            "http too often": {"http": {"url": "https://a.b/", "every": 5}},
            "a relative file": {"files": {"path": "notes.txt"}},
            "an unknown source": {"todo": {}},
        }
        for name, options in refused.items():
            self.assertTrue(wc.validate(chip("x", sources=options), SCHEMA, SCHEMA), name)


if __name__ == "__main__":
    unittest.main()
