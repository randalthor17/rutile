import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen_tokens as g  # noqa: E402


class TokenValues(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.t = g.build()

    def test_expressive_springs(self):
        e = self.t["motion"]["expressive"]
        self.assertEqual(e["spatial"]["fast"], {"damping_ratio": 0.6, "stiffness": 800})
        self.assertEqual(e["spatial"]["default"], {"damping_ratio": 0.8, "stiffness": 380})
        self.assertEqual(e["spatial"]["slow"], {"damping_ratio": 0.8, "stiffness": 200})
        self.assertEqual(e["effects"]["fast"], {"damping_ratio": 1, "stiffness": 3800})
        self.assertEqual(e["effects"]["default"], {"damping_ratio": 1, "stiffness": 1600})
        self.assertEqual(e["effects"]["slow"], {"damping_ratio": 1, "stiffness": 800})

    def test_standard_springs_differ_from_expressive(self):
        s = self.t["motion"]["standard"]["spatial"]["fast"]
        self.assertEqual(s, {"damping_ratio": 0.9, "stiffness": 1400})

    def test_corner_scale(self):
        c = self.t["shape"]["corner_dp"]
        self.assertEqual(
            {k: v for k, v in c.items() if k != "full"},
            {"none": 0, "extra_small": 4, "small": 8, "medium": 12, "large": 16,
             "large_increased": 20, "extra_large": 28, "extra_large_increased": 32,
             "extra_extra_large": 48},
        )
        self.assertEqual(c["full"], "full")

    def test_elevation(self):
        self.assertEqual(list(self.t["elevation"]["dp"].values()), [0, 1, 3, 6, 8, 12])

    def test_type_scale_spot_checks(self):
        s = self.t["type"]["styles"]
        self.assertEqual(s["body_large"], {"font": "plain", "line_height_sp": 24, "size_sp": 16,
                                           "tracking_sp": 0.5, "weight": 400})
        self.assertEqual(s["display_large"]["size_sp"], 57)
        self.assertEqual(len(s), 30)

    def test_emphasized_never_lighter_than_base(self):
        s = self.t["type"]["styles"]
        for name, style in s.items():
            if name.endswith("_emphasized"):
                base = s[name[: -len("_emphasized")]]
                self.assertGreaterEqual(style["weight"], base["weight"], name)
                self.assertEqual(style["size_sp"], base["size_sp"], name)

    def test_durations_ascend(self):
        order = [f"{g_}{i}" for g_ in ("short", "medium", "long", "extra_long") for i in range(1, 5)]
        vals = [self.t["motion"]["duration_ms"][k] for k in order]
        self.assertEqual(vals, sorted(vals))
        self.assertEqual(len(set(vals)), 16)

    def test_easings_are_valid_beziers(self):
        for name, (x1, y1, x2, y2) in self.t["motion"]["easing_cubic_bezier"].items():
            self.assertTrue(0 <= x1 <= 1 and 0 <= x2 <= 1, name)

    def test_every_group_names_known_sources(self):
        known = set(self.t["_meta"]["sources"])
        for group in ("shape", "motion", "elevation", "type"):
            src = self.t[group]["src"]
            for s in ([src] if isinstance(src, str) else src):
                self.assertIn(s, known)


class Generated(unittest.TestCase):
    def test_committed_json_is_current(self):
        self.assertEqual((ROOT / "tokens" / "m3e.json").read_text(), g.render(g.build()))

    def test_json_is_valid_and_stable(self):
        text = g.render(g.build())
        self.assertEqual(g.render(json.loads(text)), text)


class ParserFailsLoudly(unittest.TestCase):
    def test_missing_spring(self):
        with self.assertRaises(g.TokenError):
            g.parse_springs("const val SpringFastSpatialDamping = 0.6f")

    def test_unknown_weight(self):
        text = ("inline val BodyLargeWeight: FontWeight\n    get() = TypefaceTokens.WeightBlack\n")
        with self.assertRaises(g.TokenError):
            g.parse_type(text)

    def test_unknown_unit(self):
        text = ("inline val BodyLargeSize: TextUnit\n    get() = 16.em\n")
        with self.assertRaises(g.TokenError):
            g.parse_type(text)

    def test_corner_full_changed(self):
        with self.assertRaises(g.TokenError):
            g.parse_corners("val CornerValueNone = CornerSize(0.0.dp)")

    def test_checksum_mismatch_detected(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            shutil.copytree(g.SRC, tmp / "sources")
            (tmp / "sources" / "ShapeTokens.kt").write_text("tampered")
            old = g.SRC
            g.SRC = tmp / "sources"
            try:
                with self.assertRaises(g.TokenError):
                    g.verify_sources(g.load_manifest())
            finally:
                g.SRC = old
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
