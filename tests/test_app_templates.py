"""Every app template in theme/apps (D52, D58, D59) rendered by the real matugen, from the golden seed, as the shell
renders them: nothing left unrendered, and each in the format its app reads (KDE's r,g,b, qt5ct/qt6ct's 22 palette
roles, GTK's named colors, niri's KDL through `niri validate`). Skipped without matugen."""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = ROOT / "theme" / "apps"


def render():
    """{template name: rendered text}"""
    with tempfile.TemporaryDirectory() as d:
        conf = ["[config]", "version_check = false", "caching = false"]
        for t in sorted(APPS.iterdir()):
            conf += [f"[templates.{re.sub(r'[^A-Za-z0-9_-]', '-', t.name)}]", f'input_path = "{t}"',
                     f'output_path = "{d}/out/{t.name}"']
        (Path(d) / "m.toml").write_text("\n".join(conf) + "\n")
        r = subprocess.run(["matugen", "-q", "-c", f"{d}/m.toml", "color", "hex", "#134aae", "-t", "scheme-tonal-spot",
                            "-m", "dark", "--contrast", "0"], capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stderr
        return {p.name: p.read_text() for p in (Path(d) / "out").iterdir()}


@unittest.skipUnless(shutil.which("matugen"), "SKIPPED: needs matugen")
class AppTemplates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = render()

    def test_all_rendered(self):
        self.assertEqual(sorted(self.out), sorted(p.name for p in APPS.iterdir()))
        for name, text in self.out.items():
            self.assertNotIn("{{", text, name)

    def test_kde_scheme(self):
        text = self.out["kdeglobals.colors"]
        groups = re.findall(r"^\[([^\]]+)\]$", text, re.M)
        for g in ["Colors:Window", "Colors:View", "Colors:Button", "Colors:Selection", "Colors:Tooltip",
                  "Colors:Header", "Colors:Complementary", "General", "UiSettings"]:
            self.assertIn(g, groups)
        values = re.findall(r"^(\w+)=(.*)$", text, re.M)
        colors = [(k, v) for k, v in values if k.startswith(("Background", "Foreground", "Decoration"))]
        self.assertGreater(len(colors), 60)
        for k, v in colors:
            self.assertRegex(v, r"^\d{1,3},\d{1,3},\d{1,3}$", k)
            self.assertTrue(all(0 <= int(x) <= 255 for x in v.split(",")), k)
        self.assertIn("[UiSettings]\nColorScheme=Rutile", text, "what makes KF6 apps use it")
        self.assertIn("BackgroundNormal=178,197,255", text, "the selection is the palette's primary (#b2c5ff)")

    def test_qtct_palette(self):
        text = self.out["qtct.conf"]
        for group in ("active_colors", "disabled_colors", "inactive_colors"):
            row = re.search(rf"^{group}=(.*)$", text, re.M).group(1)
            entries = [e.strip() for e in row.split(",")]
            self.assertEqual(len(entries), 22, f"{group}: QPalette's roles, Accent included")
            for e in entries:
                self.assertRegex(e, r"^#ff[0-9a-f]{6}$", group)

    def test_gtk_named_colors(self):
        defined = dict(re.findall(r"@define-color (\w+) (#[0-9a-f]{6});", self.out["gtk.css"]))
        self.assertEqual(defined["accent_bg_color"], "#b2c5ff")
        for name in ("window_bg_color", "view_bg_color", "headerbar_bg_color", "theme_bg_color", "theme_selected_bg_color"):
            self.assertIn(name, defined)

    def test_gtk4_has_the_same_colors_and_sets_libadwaitas_variables(self):
        three = dict(re.findall(r"@define-color (\w+) (#[0-9a-f]{6});", self.out["gtk.css"]))
        four = dict(re.findall(r"@define-color (\w+) (#[0-9a-f]{6});", self.out["gtk4.css"]))
        self.assertEqual(three, four)
        variables = dict(re.findall(r"--([a-z-]+): @(\w+);", self.out["gtk4.css"]))
        self.assertEqual(variables["accent-bg-color"], "accent_bg_color", "what keeps the accent under adw-gtk3's sheet")
        for var, name in variables.items():
            self.assertEqual(var.replace("-", "_"), name)
            self.assertIn(name, four)
        self.assertNotIn("--", self.out["gtk.css"].split("*/", 1)[1], "GTK 3 reads no CSS variables")

    def test_niri_kdl_is_valid(self):
        if not shutil.which("niri"):
            self.skipTest("SKIPPED: needs niri")
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "rutile-colors.kdl").write_text(self.out["niri.kdl"])
            (Path(d) / "config.kdl").write_text('include optional=true "rutile-colors.kdl"\n')
            r = subprocess.run(["niri", "validate", "-c", f"{d}/config.kdl"], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
