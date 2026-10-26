"""tools/gen_settings.py: the settings schema (D45) is one the shell and the Nix module understand, and the
generated SettingsSchema.js matches it."""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen_settings as g  # noqa: E402

SCHEMA = json.loads((ROOT / "settings" / "schema.json").read_text())


def with_leaf(leaf, name="x"):
    s = copy.deepcopy(SCHEMA)
    s["properties"]["motion"]["properties"][name] = leaf
    return s


class Generated(unittest.TestCase):
    def test_committed_file_is_current_and_marked(self):
        _, text = g.build()
        self.assertEqual(g.OUT.read_text(), text, "stale: run make generate")
        self.assertTrue(text.startswith(g.MARK))

    def test_shipped_schema_is_supported(self):
        self.assertEqual(g.problems(SCHEMA), [])

    def test_every_leaf_has_a_title(self):
        def walk(node, path):
            for name, child in node["properties"].items():
                if child["type"] == "object":
                    walk(child, path + name + ".")
                else:
                    self.assertTrue(child.get("title"), path + name)
        walk(SCHEMA, "")


class Problems(unittest.TestCase):
    def test_supported_leaves(self):
        for leaf in ({"type": "boolean", "default": True}, {"type": "integer", "minimum": 0, "default": 0},
                     {"type": "string", "enum": ["a", "b"], "default": "a"},
                     {"type": "array", "items": {"type": "string"}}):
            self.assertEqual(g.problems(with_leaf(leaf)), [], leaf)

    def test_rejects_what_the_shell_or_nix_would_not_understand(self):
        for leaf, why in (({"type": "null"}, "type"), ({"type": ["string", "null"]}, "type"),
                          ({"type": "string", "pattern": "x"}, "unsupported keys"),
                          ({"type": "array", "items": {"type": "array", "items": {"type": "string"}}}, "items"),
                          ({"type": "array"}, "items"),
                          ({"type": "array", "items": {"type": "string", "oneOf": []}}, "unsupported keys")):
            got = g.problems(with_leaf(leaf))
            self.assertTrue(any(why in p for p in got), f"{leaf}: {got}")
        got = g.problems(with_leaf({"type": "string"}, name="bad-name"))
        self.assertTrue(any("names are" in p for p in got), got)
        got = g.problems(with_leaf({"type": "string"}, name="9lives"))
        self.assertTrue(any("names are" in p for p in got), got)
        got = g.problems(with_leaf({"type": "object", "properties": {}, "additionalProperties": False}))
        self.assertTrue(any("unsupported keys" in p for p in got), got)
        got = g.problems(with_leaf({"type": "object"}))
        self.assertTrue(any("must be an object with properties" in p for p in got), got)

    def test_defaults_must_fit(self):
        for leaf in ({"type": "number", "minimum": 0, "default": -1}, {"type": "number", "maximum": 1, "default": 2},
                     {"type": "integer", "default": 1.5}, {"type": "integer", "default": True},
                     {"type": "boolean", "default": 0}, {"type": "string", "enum": ["a"], "default": "b"},
                     {"type": "array", "items": {"type": "string"}, "default": [1]},
                     {"type": "number", "default": "1"}, {"type": "number", "default": True}):
            got = g.problems(with_leaf(leaf))
            self.assertTrue(any("default" in p for p in got), f"{leaf}: {got}")
        for leaf in ({"type": "number", "minimum": 0, "maximum": 1, "default": 0},
                     {"type": "number", "minimum": 0, "maximum": 1, "default": 1},
                     {"type": "number", "default": 2}, {"type": "array", "items": {"type": "string"}, "default": []}):
            self.assertEqual(g.problems(with_leaf(leaf)), [], leaf)


if __name__ == "__main__":
    unittest.main()
