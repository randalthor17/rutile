import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen_qml as g  # noqa: E402

COMMON = ROOT / "shell" / "common"


class Generated(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = g.build()
        cls.roles = json.loads((ROOT / "theme" / "roles.json").read_text())["roles"]

    def test_committed_files_are_current(self):
        for name, text in self.files.items():
            self.assertEqual((COMMON / name).read_text(), text, f"{name} is stale: run make generate")

    def test_every_generated_file_is_marked(self):
        for name, text in self.files.items():
            self.assertTrue(text.startswith(g.MARK), name)

    def test_one_color_property_per_role(self):
        text = self.files["Colors.qml"]
        props = re.findall(r"readonly property color (\w+):", text)
        self.assertEqual(props, [g.qml_name(r) for r in self.roles])
        self.assertEqual(len(props), 49)
        self.assertEqual(len(set(props)), 49)

    def test_no_property_looks_like_a_signal_handler(self):
        for name, text in self.files.items():
            for prop in re.findall(r"property \w+ (\w+):", text):
                self.assertIsNone(re.match(r"on[A-Z]", prop), f"{name}: {prop}")

    def test_qml_name_rules(self):
        cases = {"primary": "primary", "on_primary": "primaryOn", "on_surface_variant": "surfaceVariantOn",
                 "inverse_on_surface": "inverseOnSurface", "surface_container_high": "surfaceContainerHigh",
                 "on_primary_fixed_variant": "primaryFixedVariantOn"}
        for role, want in cases.items():
            self.assertEqual(g.qml_name(role), want)

    def test_roles_array_keeps_snake_case_order(self):
        m = re.search(r"readonly property var roles: (\[.*?\])\n", self.files["Colors.qml"])
        self.assertEqual(json.loads(m.group(1)), self.roles)

    def test_fallback_is_the_golden_palette(self):
        golden = json.loads((ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json").read_text())
        m = re.search(r"property var tables: \((\{.*\})\)\n", self.files["Colors.qml"])
        tables = json.loads(m.group(1))
        for mode in ("dark", "light"):
            for role in self.roles:
                self.assertEqual(tables[mode][role], golden["colors"][mode][role])

    def test_imports_match_what_each_file_needs(self):
        self.assertIn("import QtQuick\n", self.files["Colors.qml"])  # `color` needs QtQuick
        for name in ("Shapes.qml", "Elevation.qml", "Motion.qml", "Type.qml"):
            self.assertIn("import QtQml\n", self.files[name])

    def test_shapes_pill_radius(self):
        self.assertIn("readonly property int full: 9999", self.files["Shapes.qml"])


class Guards(unittest.TestCase):
    def test_collision_is_rejected(self):
        old = g.qml_name
        g.qml_name = lambda r: "same"
        try:
            with self.assertRaises(SystemExit):
                g.build()
        finally:
            g.qml_name = old

    def test_signal_handler_lookalike_is_rejected(self):
        old, counter = g.qml_name, iter(range(1000))
        g.qml_name = lambda r: f"onThing{next(counter)}"
        try:
            with self.assertRaises(SystemExit) as cm:
                g.build()
            self.assertIn("signal handlers", str(cm.exception))
        finally:
            g.qml_name = old


class HandWrittenFiles(unittest.TestCase):
    def test_expected_files_exist(self):
        for name in ("Spacing.qml", "Spring.qml", "SpringMath.js", "PaletteWatcher.qml"):
            self.assertTrue((COMMON / name).exists(), name)

    def test_only_palette_watcher_needs_quickshell(self):
        users = sorted(p.name for p in COMMON.iterdir() if "import Quickshell" in p.read_text())
        self.assertEqual(users, ["PaletteWatcher.qml"])


if __name__ == "__main__":
    unittest.main()
