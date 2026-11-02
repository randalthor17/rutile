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


def render(mode="dark"):
    """{template name: rendered text}"""
    with tempfile.TemporaryDirectory() as d:
        conf = ["[config]", "version_check = false", "caching = false"]
        for t in sorted(APPS.iterdir()):
            conf += [f"[templates.{re.sub(r'[^A-Za-z0-9_-]', '-', t.name)}]", f'input_path = "{t}"',
                     f'output_path = "{d}/out/{t.name}"']
        (Path(d) / "m.toml").write_text("\n".join(conf) + "\n")
        r = subprocess.run(["matugen", "-q", "-c", f"{d}/m.toml", "color", "hex", "#134aae", "-t", "scheme-tonal-spot",
                            "-m", mode, "--contrast", "0"], capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stderr
        return {p.name: p.read_text() for p in (Path(d) / "out").iterdir()}


def pywalfox_contrasts(colors, mode):
    """{(text role, background role): contrast ratio} for the pairs Firefox shows, from Pywalfox 2.x's
    EXTENDED_PYWAL_COLORS, its palette templates and changeLuminance (src/config/default-themes.ts,
    src/utils/colors.ts)."""
    def luminance_changed(hex_, lum, lo=0, hi=255):
        return "#" + "".join(f"{round(min(max(lo, c + c * lum), hi)):02x}"
                             for c in (int(hex_[i:i + 2], 16) for i in (1, 3, 5)))
    full = list(colors) + [luminance_changed(colors[0], 1.25), "#ffffff", luminance_changed(colors[0], 1.85),
                           luminance_changed(colors[7], 0.1, 205, 220)]
    roles = ({"background": 0, "backgroundLight": 16, "backgroundExtra": 18, "text": 15, "textFocus": 17}
             if mode == "dark" else
             {"background": 19, "backgroundLight": 17, "backgroundExtra": 7, "text": 16, "textFocus": 0})

    def lum(hex_):
        c = [int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    pairs = [("text", "background"), ("textFocus", "backgroundLight"), ("text", "backgroundLight"),
             ("textFocus", "backgroundExtra"), ("textFocus", "background")]
    out = {}
    for t, g in pairs:
        a, b = sorted((lum(full[roles[t]]), lum(full[roles[g]])), reverse=True)
        out[(t, g)] = (a + 0.05) / (b + 0.05)
    return out


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

    def test_pywalfox_text_reads_in_both_modes(self):
        # Pywalfox builds Firefox's theme from colors 0-15 with its own templates, and its light one reads them as
        # pywal's dark palette (color0 is the text); its palette math, ported, must give readable text either way
        for mode, out in (("dark", self.out), ("light", render("light"))):
            colors = dict(re.findall(r"^(color\d+) (#[0-9a-f]{6})$", out["pywalfox.conf"], re.M))
            self.assertIn(f"mode {mode}\n", out["pywalfox.conf"])
            for (text, ground), ratio in pywalfox_contrasts([colors[f"color{i}"] for i in range(16)], mode).items():
                self.assertGreaterEqual(ratio, 4.5, f"{mode}: {text} on {ground}")

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
