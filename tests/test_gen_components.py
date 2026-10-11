import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen_components as gc  # noqa: E402
import gen_tokens  # noqa: E402

CORNERS = json.loads((ROOT / "tokens" / "m3e.json").read_text())["shape"]["corner_dp"]


class Committed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = gc.build()

    def test_committed_json_is_current(self):
        self.assertEqual((ROOT / "tokens" / "components.json").read_text(), gc.render(self.data))

    def test_state_opacities(self):
        self.assertEqual(self.data["state_opacity"], {
            "hover": 0.08, "focus": 0.1, "pressed": 0.1, "dragged": 0.16,
            "disabled_container": 0.1, "disabled_content": 0.38})

    def test_button_heights_and_icons(self):
        sizes = self.data["button"]["sizes"]
        self.assertEqual([sizes[k]["height"] for k in ("xs", "s", "m", "l", "xl")], [32, 40, 56, 96, 136])
        self.assertEqual([sizes[k]["icon"] for k in ("xs", "s", "m", "l", "xl")], [20, 20, 24, 32, 40])

    def test_xs_button_corrections_are_applied_and_recorded(self):
        xs = self.data["button"]["sizes"]["xs"]
        self.assertEqual((xs["leading"], xs["trailing"], xs["icon_label_gap"]), (12, 12, 4))
        # the other sizes keep the token values
        s = self.data["button"]["sizes"]["s"]
        self.assertEqual((s["leading"], s["trailing"], s["icon_label_gap"]), (16, 16, 8))
        rec = self.data["_meta"]["corrections"]["button.sizes.xs"]
        self.assertEqual(rec["applied"], {"leading": 12, "trailing": 12, "icon_label_gap": 4})

    def test_label_style_follows_the_text_style_for_height_rule(self):
        styles = {k: v["label_style"] for k, v in self.data["button"]["sizes"].items()}
        self.assertEqual(styles, {"xs": "label_large", "s": "label_large", "m": "title_medium",
                                  "l": "headline_small", "xl": "headline_large"})

    def test_shapes_resolve_to_px_or_full(self):
        for size in self.data["button"]["sizes"].values():
            for key in ("shape_round", "shape_square", "shape_pressed", "shape_selected_round", "shape_selected_square"):
                v = size[key]
                self.assertTrue(v == "full" or v in CORNERS.values(), (key, v))
        m = self.data["button"]["sizes"]["m"]
        self.assertEqual((m["shape_round"], m["shape_square"], m["shape_pressed"]), ("full", 16, 12))

    def test_icon_button_default_width_is_square_and_variants_are_ordered(self):
        for key, spec in self.data["icon_button"]["sizes"].items():
            w = spec["width"]
            self.assertEqual(w["default"], spec["height"], key)
            self.assertLess(w["narrow"], w["default"], key)
            self.assertLess(w["default"], w["wide"], key)
            self.assertEqual(w["default"], spec["icon"] + 2 * spec["padding"]["default"], key)

    def test_every_type_defines_every_role_key(self):
        keys = {"container", "content", "outline", "selected_container", "selected_content",
                "unselected_container", "unselected_content", "disabled_container", "disabled_content"}
        for group in ("button", "icon_button"):
            for name, t in self.data[group]["types"].items():
                self.assertEqual(set(t), keys, f"{group}/{name}")
                for k in ("content", "selected_content", "unselected_content", "disabled_content"):
                    self.assertIsNotNone(t[k], f"{group}/{name}/{k}")

    def test_known_role_mappings(self):
        b = self.data["button"]["types"]
        self.assertEqual((b["filled"]["container"], b["filled"]["content"]), ("primary", "on_primary"))
        self.assertEqual(b["tonal"]["container"], "secondary_container")
        self.assertEqual(b["elevated"]["container"], "surface_container_low")
        self.assertEqual(b["outlined"]["outline"], "outline_variant")
        self.assertIsNone(b["outlined"]["container"])
        self.assertIsNone(b["text"]["container"])
        # a text button has no toggle colors of its own, so toggling keeps its content color
        self.assertEqual(b["text"]["selected_content"], b["text"]["content"])
        i = self.data["icon_button"]["types"]
        self.assertEqual(i["filled"]["unselected_container"], "surface_container")
        self.assertEqual(i["tonal"]["selected_container"], "secondary")


class FailsLoudly(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.real = gen_tokens.SRC
        self.addCleanup(lambda: setattr(gen_tokens, "SRC", self.real) or setattr(gc, "SRC", self.real))

    def with_modified_source(self, name, edit):
        shutil.copytree(self.real, self.tmp / "src")
        p = self.tmp / "src" / name
        text = p.read_text()
        new = edit(text)
        self.assertNotEqual(text, new, "test edit did not change the file")
        p.write_text(new)
        gc.SRC = gen_tokens.SRC = self.tmp / "src"

    def test_missing_xs_todo_forces_a_review(self):
        self.with_modified_source("Button.kt", lambda t: t.replace("once it's been corrected", "once it was fixed"))
        with self.assertRaises(gc.ComponentError) as cm:
            gc.button_corrections()
        self.assertIn("corrected upstream", str(cm.exception))

    def test_changed_text_style_rule_is_detected(self):
        self.with_modified_source("Button.kt", lambda t: t.replace("MaterialTheme.typography.titleMedium",
                                                                   "MaterialTheme.typography.titleLarge", 1))
        with self.assertRaises(gc.ComponentError):
            gc.label_styles()

    def test_tampered_token_file_fails_the_checksum(self):
        self.with_modified_source("FilledButtonTokens.kt", lambda t: t + "\n// tampered\n")
        with self.assertRaises(gen_tokens.TokenError):
            gc.build()

    def test_parsers_reject_unexpected_expressions(self):
        with self.assertRaises(gc.ComponentError):
            gc.dp("16.sp", "x")
        with self.assertRaises(gc.ComponentError):
            gc.shape("ShapeKeyTokens.CornerNope", CORNERS, "x")
        with self.assertRaises(gc.ComponentError):
            gc.shape("16.dp", CORNERS, "x")
        with self.assertRaises(gc.ComponentError):
            gc.role("Color.Red", "x")
        with self.assertRaises(gc.ComponentError):
            gc.pick({}, "ContainerHeight", "x")

    def test_parsers_accept_expected_expressions(self):
        self.assertEqual(gc.dp("16.0.dp", "x"), 16)
        self.assertEqual(gc.dp("0.5.dp", "x"), 0.5)
        self.assertEqual(gc.shape("ShapeKeyTokens.CornerFull", CORNERS, "x"), "full")
        self.assertEqual(gc.shape("ShapeKeyTokens.CornerExtraLarge", CORNERS, "x"), 28)
        self.assertEqual(gc.role("ColorSchemeKeyTokens.OnSurfaceVariant", "x"), "on_surface_variant")


if __name__ == "__main__":
    unittest.main()
