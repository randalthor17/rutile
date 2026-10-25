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


if __name__ == "__main__":
    unittest.main()
