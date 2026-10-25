import json
import math
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
        # `color` and Qt.font() need QtQuick; pure data singletons only need QtQml.
        for name in ("Colors.qml", "Type.qml"):
            self.assertIn("import QtQuick\n", self.files[name])
        for name in ("Shapes.qml", "Elevation.qml", "Motion.qml", "Fonts.qml"):
            self.assertIn("import QtQml\n", self.files[name])

    def test_fonts_come_from_fonts_json(self):
        fonts = json.loads((ROOT / "theme" / "fonts.json").read_text())
        text, icons = fonts["text"]["family"], fonts["icons"]["family"]
        self.assertIn(f'readonly property string textFamily: "{text}"', self.files["Fonts.qml"])
        self.assertIn(f'readonly property string iconFamily: "{icons}"', self.files["Fonts.qml"])
        self.assertIn(f'property string plainFamily: "{text}"', self.files["Type.qml"])
        self.assertIn(f'property string brandFamily: "{text}"', self.files["Type.qml"])
        self.assertIn("function font(style)", self.files["Type.qml"])
        axes = re.search(r"readonly property var textAxes: \((\{.*\})\)\n", self.files["Fonts.qml"])
        self.assertEqual(json.loads(axes.group(1)), fonts["text"]["axes"])

    def test_unsafe_family_name_is_rejected(self):
        real = g.ROOT
        import tempfile, shutil
        tmp = Path(tempfile.mkdtemp())
        try:
            shutil.copytree(real / "theme", tmp / "theme")
            shutil.copytree(real / "tokens", tmp / "tokens")
            data = json.loads((tmp / "theme" / "fonts.json").read_text())
            data["text"]["family"] = 'Evil"; import os; "'
            (tmp / "theme" / "fonts.json").write_text(json.dumps(data))
            g.ROOT = tmp
            with self.assertRaises(SystemExit):
                g.build()
        finally:
            g.ROOT = real
            shutil.rmtree(tmp, ignore_errors=True)

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


class EffectsCurve(unittest.TestCase):
    """The bezier that stands in for a critically damped spring (EffectsColor, EffectsNumber)."""

    @staticmethod
    def bezier_y(x, p):
        a, b, c, d = p
        lo, hi = 0.0, 1.0
        for _ in range(50):
            s = (lo + hi) / 2
            xs = 3 * (1 - s) ** 2 * s * a + 3 * (1 - s) * s * s * c + s ** 3
            lo, hi = (s, hi) if xs < x else (lo, s)
        s = (lo + hi) / 2
        return 3 * (1 - s) ** 2 * s * b + 3 * (1 - s) * s * s * d + s ** 3

    def test_settle_point_is_within_one_255th(self):
        wt = g.SETTLE_WT
        self.assertAlmostEqual((1 + wt) * math.exp(-wt), 1 / 255, places=6)

    def test_bezier_follows_the_spring_within_two_percent_and_never_overshoots(self):
        worst = 0
        for i in range(201):
            u = i / 200
            t = u * g.SETTLE_WT
            spring = 1 - (1 + t) * math.exp(-t)
            y = self.bezier_y(u, g.CRITICAL_BEZIER)
            self.assertLessEqual(y, 1 + 1e-9)
            worst = max(worst, abs(y - spring))
        self.assertLess(worst, 0.02)

    def test_durations_follow_stiffness_and_refuse_underdamped_springs(self):
        curves = g.effects_curves({"fast": {"stiffness": 3800, "damping_ratio": 1},
                                    "slow": {"stiffness": 800, "damping_ratio": 1}})
        self.assertEqual((curves["fast"]["duration"], curves["slow"]["duration"]), (125, 272))
        with self.assertRaises(ValueError):
            g.effects_curves({"x": {"stiffness": 800, "damping_ratio": 0.8}})
