import copy
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import palette as pal  # noqa: E402

FIXTURE = ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json"
MATUGEN = os.environ.get("RUTILE_MATUGEN") or shutil.which("matugen")

try:
    from materialyoucolor.hct import Hct
    from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors as MDC
    import materialyoucolor.scheme.scheme_tonal_spot  # noqa: F401
    HAVE_REF = True
except ImportError:
    HAVE_REF = False

need_matugen = unittest.skipUnless(MATUGEN, "matugen not found (set RUTILE_MATUGEN); SKIPPED")
need_ref = unittest.skipUnless(HAVE_REF, "materialyoucolor not installed (pip install materialyoucolor); SKIPPED")


def golden():
    return json.loads(FIXTURE.read_text())


class Validator(unittest.TestCase):
    def test_golden_is_valid(self):
        self.assertEqual(pal.validate(golden()), [])

    def test_roles_file_covers_surface_containers(self):
        roles = set(pal.required_roles())
        for r in ("surface_container_lowest", "surface_container_low", "surface_container",
                  "surface_container_high", "surface_container_highest", "primary", "on_primary_container"):
            self.assertIn(r, roles)
        self.assertEqual(len(roles), 49)

    def test_rejects_missing_role(self):
        d = golden()
        del d["colors"]["dark"]["primary"]
        self.assertTrue(any("missing roles" in e for e in pal.validate(d)))

    def test_rejects_bad_hex(self):
        d = golden()
        d["colors"]["light"]["primary"] = "#12345"
        self.assertTrue(any("not #rrggbb" in e for e in pal.validate(d)))
        d["colors"]["light"]["primary"] = "#ABCDEF"  # uppercase is not our format
        self.assertTrue(any("not #rrggbb" in e for e in pal.validate(d)))

    def test_rejects_unexpected_role_wrong_format_wrong_mode(self):
        d = golden()
        d["colors"]["dark"]["bogus"] = "#000000"
        d["format"] = 2
        d["mode"] = "sepia"
        errs = " | ".join(pal.validate(d))
        self.assertIn("unexpected role 'bogus'", errs)
        self.assertIn("format must be 1", errs)
        self.assertIn("mode must be", errs)

    def test_rejects_wrong_top_level_shapes(self):
        self.assertTrue(pal.validate([]))
        d = golden()
        d["colors"] = {"dark": d["colors"]["dark"]}
        self.assertTrue(pal.validate(d))

    def test_render_rejects_bad_inputs_without_running_matugen(self):
        for kw in ({"seed": "red"}, {"scheme": "scheme-nope"}, {"contrast": 2}):
            args = dict(seed="#134aae", scheme="scheme-tonal-spot", mode="dark", contrast=0.0)
            args.update(kw)
            with self.assertRaises(pal.PaletteError):
                pal.render(out="/tmp/never-written.json", matugen="/nonexistent/matugen", **args)
        self.assertFalse(os.path.exists("/tmp/never-written.json"))

    def test_render_takes_a_seed_or_an_image_not_both_or_neither(self):
        base = dict(scheme="scheme-tonal-spot", mode="dark", contrast=0.0, out="/tmp/never-written.json",
                    matugen="/nonexistent/matugen")
        for kw, why in (({"seed": None}, "not both or neither"),
                        ({"seed": "#134aae", "image": __file__}, "not both or neither"),
                        ({"seed": None, "image": "/nonexistent.png"}, "image not found")):
            with self.assertRaisesRegex(pal.PaletteError, why, msg=kw):
                pal.render(**base, **kw)
        self.assertFalse(os.path.exists("/tmp/never-written.json"))


def solid_png(path, rgb, size=32):
    """A PNG of one color, written without an imaging library."""
    import struct
    import zlib
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + bytes(rgb) * size for _ in range(size))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


@need_matugen
class WithMatugen(unittest.TestCase):
    def render(self, **kw):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        args = dict(seed="#134aae", scheme="scheme-tonal-spot", mode="dark", contrast=0.0)
        args.update(kw)
        out = d / "palette.json"
        pal.render(out=str(out), matugen=MATUGEN, **args)
        return json.loads(out.read_text()), out

    def test_render_matches_golden(self):
        doc, _ = self.render()
        ver = subprocess.run([MATUGEN, "--version"], capture_output=True, text=True).stdout.strip()
        made = {k: doc.pop(k) for k in ("scheme", "contrast")}
        self.assertEqual(made, {"scheme": "scheme-tonal-spot", "contrast": 0.0},
                         "how it was made, for tools/apptheme.py (D52)")
        self.assertEqual(doc, golden(), f"output drifted from golden with {ver}; review before updating the fixture")

    def test_both_modes_in_every_file(self):
        dark, _ = self.render(mode="dark")
        light, _ = self.render(mode="light")
        self.assertEqual(dark["colors"], light["colors"])
        self.assertEqual((dark["mode"], light["mode"]), ("dark", "light"))
        self.assertNotEqual(dark["colors"]["dark"]["surface"], dark["colors"]["light"]["surface"])

    def test_every_scheme_type_renders_valid(self):
        for scheme in pal.SCHEMES:
            doc, _ = self.render(scheme=scheme)
            self.assertEqual(pal.validate(doc), [], scheme)

    def test_an_image_seeds_the_palette_with_its_color(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        green, red = d / "green.png", d / "red.png"
        solid_png(green, (0x2e, 0x7d, 0x32))
        solid_png(red, (0xc6, 0x28, 0x28))
        g, _ = self.render(seed=None, image=str(green))
        r, _ = self.render(seed=None, image=str(red))
        self.assertEqual(pal.validate(g), [])
        primary = lambda doc: [int(doc["colors"]["dark"]["primary"][i:i + 2], 16) for i in (1, 3, 5)]
        pg, pr = primary(g), primary(r)
        self.assertEqual(max(range(3), key=lambda i: pg[i]), 1, f"green image, green primary: {pg}")
        self.assertEqual(max(range(3), key=lambda i: pr[i]), 0, f"red image, red primary: {pr}")

    def test_contrast_changes_output(self):
        base, _ = self.render(contrast=0.0)
        high, _ = self.render(contrast=1.0)
        self.assertNotEqual(base["colors"], high["colors"])

    def test_atomic_write_and_permissions(self):
        _, out = self.render()
        self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o644)
        self.assertEqual([p.name for p in out.parent.iterdir()], ["palette.json"])

    def test_failed_render_keeps_previous_palette(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        out = d / "palette.json"
        pal.render("#134aae", "scheme-tonal-spot", "dark", 0.0, str(out), MATUGEN)
        before = out.read_text()
        broken = d / "fake-matugen"
        broken.write_text("#!/bin/sh\nexit 1\n")
        broken.chmod(0o755)
        with self.assertRaises(pal.PaletteError):
            pal.render("#134aae", "scheme-tonal-spot", "dark", 0.0, str(out), str(broken))
        self.assertEqual(out.read_text(), before)
        self.assertEqual(sorted(p.name for p in d.iterdir()), ["fake-matugen", "palette.json"])

    def test_cli_validate_exit_codes(self):
        _, out = self.render()
        run = lambda *a: subprocess.run([sys.executable, str(ROOT / "tools" / "palette.py"), *a],
                                        capture_output=True, text=True).returncode
        self.assertEqual(run("validate", str(out)), 0)
        bad = out.parent / "bad.json"
        bad.write_text("{}")
        self.assertEqual(run("validate", str(bad)), 1)


# Roles where matugen's color math is known to differ from the reference
# implementation (spec 2021). Found by measurement, see docs/theme.md.
KNOWN_2021_DIVERGENCE = {
    "on_primary_container", "on_secondary_container", "on_tertiary_container", "on_error_container",
    "on_surface_variant", "outline", "outline_variant", "surface_variant", "secondary_container",
}


@need_matugen
@need_ref
class AgainstReference(unittest.TestCase):
    """Cross-check matugen against an independent Material Color Utilities port."""

    SCHEMES = {
        "scheme-tonal-spot": "scheme_tonal_spot.SchemeTonalSpot",
        "scheme-content": "scheme_content.SchemeContent",
        "scheme-expressive": "scheme_expressive.SchemeExpressive",
        "scheme-fidelity": "scheme_fidelity.SchemeFidelity",
        "scheme-fruit-salad": "scheme_fruit_salad.SchemeFruitSalad",
        "scheme-monochrome": "scheme_monochrome.SchemeMonochrome",
        "scheme-neutral": "scheme_neutral.SchemeNeutral",
        "scheme-rainbow": "scheme_rainbow.SchemeRainbow",
        "scheme-vibrant": "scheme_vibrant.SchemeVibrant",
    }

    @staticmethod
    def camel(n):
        return re.sub(r"_(\w)", lambda m: m.group(1).upper(), n)

    def scheme_cls(self, name):
        import importlib
        mod, cls = self.SCHEMES[name].split(".")
        return getattr(importlib.import_module("materialyoucolor.scheme." + mod), cls)

    def matugen_colors(self, seed, scheme):
        out = subprocess.run([MATUGEN, "-q", "color", "hex", seed, "-t", scheme, "--json", "hex", "--dry-run"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)["colors"]

    def compare(self, spec):
        total = bad = 0
        bad_roles = set()
        for seed in ("#134aae", "#6750a4"):
            for scheme in self.SCHEMES:
                mc = self.matugen_colors(seed, scheme)
                for dark in (True, False):
                    s = self.scheme_cls(scheme)(Hct.from_int(0xFF000000 | int(seed[1:], 16)), dark, 0.0, spec)
                    for role in pal.required_roles():
                        want = "#%06x" % (getattr(MDC, self.camel(role)).get_hct(s).to_int() & 0xFFFFFF)
                        got = mc[role]["dark" if dark else "light"]["color"].lower()
                        total += 1
                        if got != want:
                            bad += 1
                            bad_roles.add(role)
        return total, bad, bad_roles

    def test_agrees_with_2021_spec_except_known_roles(self):
        total, bad, roles = self.compare("2021")
        # Measured: 94 of 1764 values differ (94.7% agreement) at contrast 0. The bound
        # guards against regressions; the role-set check below is the stricter one.
        self.assertGreaterEqual(1 - bad / total, 0.93, f"{bad}/{total} differ")
        self.assertLessEqual(roles, KNOWN_2021_DIVERGENCE, f"new divergent roles: {roles - KNOWN_2021_DIVERGENCE}")

    def test_tonal_spot_primary_matches_reference_2021(self):
        s = self.scheme_cls("scheme-tonal-spot")(Hct.from_int(0xFF134AAE), True, 0.0, "2021")
        want = "#%06x" % (MDC.primary.get_hct(s).to_int() & 0xFFFFFF)
        self.assertEqual(golden()["colors"]["dark"]["primary"], want)

    def test_documents_that_matugen_is_not_2025_spec(self):
        """If this fails, matugen gained 2025-spec support: revisit docs/theme.md and the plan."""
        total, bad, _ = self.compare("2025")
        self.assertGreater(bad / total, 0.2, "matugen now agrees with the 2025 spec; update docs/theme.md")


if __name__ == "__main__":
    unittest.main()
