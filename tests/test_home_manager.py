"""The home-manager module (nix/home-manager.nix, D45, D55): its settings options come from settings/schema.json, and
what is set lands in managed.json; `enable` gives the user service, the package, and niri's part (the layer rule,
opt-in binds, the optional include of the shell's niri colors), into home-manager's niri config when that is on,
else a file; the KDL passes `niri validate`.
Evaluated with nixpkgs from NIX_PATH and stand-ins for home-manager; skipped (loudly) without nix or nixpkgs."""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "tests" / "nix" / "hm-eval.nix"
MODULE_EVAL = ROOT / "tests" / "nix" / "hm-module.nix"
MODULE = ROOT / "nix" / "home-manager.nix"


def evaluate(settings):
    """(managed.json as an object, or "none" when nothing is written; error text)"""
    expr = f"import {EVAL} {{ module = {MODULE}; settings = {settings}; }}"
    r = subprocess.run(["nix-instantiate", "--eval", "--strict", "--read-write-mode", "-E", expr],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        return None, r.stderr
    text = json.loads(r.stdout)          # a Nix string prints as a JSON string
    return (text if text == "none" else json.loads(text)), ""


def module(cfg, niri=False):
    """What `programs.rutile = cfg` makes (service, packages, files, niri), or None and the error."""
    expr = (f"import {MODULE_EVAL} {{ module = {MODULE}; cfg = {cfg}; niriModule = {'true' if niri else 'false'}; }}")
    r = subprocess.run(["nix-instantiate", "--eval", "--strict", "--read-write-mode", "-E", expr],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        return None, r.stderr
    return json.loads(json.loads(r.stdout)), ""


def niri_valid(kdl):
    """(valid, output) from `niri validate`, or None without niri."""
    if not shutil.which("niri"):
        return None
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "config.kdl"
        f.write_text(kdl)
        r = subprocess.run(["niri", "validate", "-c", str(f)], capture_output=True, text=True, timeout=60)
        return r.returncode == 0, r.stdout + r.stderr


def nixpkgs_available():
    if not shutil.which("nix-instantiate"):
        return False
    r = subprocess.run(["nix-instantiate", "--eval", "-E", "(import <nixpkgs> { }).lib.version"],
                       capture_output=True, text=True, timeout=120)
    return r.returncode == 0


@unittest.skipUnless(nixpkgs_available(), "SKIPPED: needs nix-instantiate and <nixpkgs> on NIX_PATH")
class HomeManagerModule(unittest.TestCase):
    def test_writes_only_what_is_set(self):
        got, err = evaluate("{ motion.speed = 1.5; }")
        self.assertEqual(got, {"motion": {"speed": 1.5}}, err)

    def test_lists_and_empty_lists(self):
        self.assertEqual(evaluate('{ shelf.pins = [ "foot" "firefox" ]; }')[0], {"shelf": {"pins": ["foot", "firefox"]}})
        self.assertEqual(evaluate("{ shelf.pins = [ ]; }")[0], {"shelf": {"pins": []}}, "an empty shelf is a choice")

    def test_nothing_set_writes_no_file(self):
        self.assertEqual(evaluate("{ }")[0], "none")

    def test_the_schema_limits_apply(self):
        for bad in ("{ motion.speed = 9; }", "{ motion.speed = -1; }", '{ motion.speed = "fast"; }',
                    "{ shelf.pins = [ 1 ]; }", "{ motion.nope = 1; }"):
            got, err = evaluate(bad)
            self.assertIsNone(got, bad)
            self.assertIn("error:", err, bad)

    def test_limits_are_inclusive(self):
        self.assertEqual(evaluate("{ motion.speed = 0; }")[0], {"motion": {"speed": 0}})
        self.assertEqual(evaluate("{ motion.speed = 4; }")[0], {"motion": {"speed": 4}})


@unittest.skipUnless(nixpkgs_available(), "SKIPPED: needs nix-instantiate and <nixpkgs> on NIX_PATH")
class ShellModule(unittest.TestCase):
    def test_off_by_default_does_nothing(self):
        got, err = module("{ }")
        self.assertEqual((got["packages"], got["service"], got["files"]), ([], None, []), err)

    def test_enable_gives_the_service_and_the_command(self):
        got, err = module("{ enable = true; }")
        self.assertEqual(got["failed"], [], err)
        self.assertEqual(got["packages"], ["rutile-shell"])
        svc = got["service"]
        self.assertEqual(svc["Service"]["ExecStart"], got["exe"])
        self.assertEqual(svc["Service"]["Restart"], "on-failure")
        self.assertEqual(svc["Install"]["WantedBy"], ["graphical-session.target"])
        self.assertEqual(svc["Unit"]["PartOf"], ["graphical-session.target"], "stops with the session")
        got, _ = module('{ enable = true; systemd.enable = false; }')
        self.assertIsNone(got["service"], "no service: start it from niri yourself")
        self.assertEqual(module('{ enable = true; systemd.target = "niri.service"; }')[0]["service"]["Install"]["WantedBy"],
                         ["niri.service"])

    def test_without_a_package_it_says_so(self):
        expr = f"import {MODULE_EVAL} {{ module = {MODULE}; cfg = {{ enable = true; package = null; }}; }}"
        r = subprocess.run(["nix-instantiate", "--eval", "--strict", "--read-write-mode", "-E", expr],
                           capture_output=True, text=True, timeout=300)
        self.assertIn("programs.rutile.package is not set", json.loads(json.loads(r.stdout))["failed"][0])

    def test_niri_without_its_module_gets_a_file_to_include(self):
        got, err = module("{ enable = true; }")
        self.assertIn("niri/rutile.kdl", got["files"], err)
        kdl = got["niriFile"]
        self.assertIn('match namespace="^rutile-(power|polkit)$"', kdl)
        self.assertIn("xray false", kdl)
        self.assertIn('include optional=true "/home/test/.config/niri/rutile-colors.kdl"', kdl,
                      "the shell's niri colors, when that switch is on (the file is missing otherwise: still valid)")
        self.assertNotIn("binds", kdl, "binds are opt-in")
        valid = niri_valid(kdl)
        if valid is not None:
            self.assertTrue(valid[0], valid[1])
        self.assertNotIn("niri/rutile.kdl", module("{ enable = true; niri.enable = false; }")[0]["files"])

    def test_niri_with_its_module_is_included_and_valid(self):
        got, err = module("{ enable = true; niri.binds.enable = true; }", niri=True)
        self.assertNotIn("niri/rutile.kdl", got["files"], err)
        self.assertRegex(got["extraConfig"], r'include "/nix/store/[^"]+-rutile\.kdl"')
        kdl = got["included"]
        self.assertIn(f'XF86AudioRaiseVolume allow-when-locked=true {{ spawn "{got["exe"]}" "ipc" "call" "osd" "volumeUp"; }}', kdl)
        self.assertIn(f'Mod+Alt+L {{ spawn "{got["exe"]}" "ipc" "call" "lock" "lock"; }}', kdl, "only media keys when locked")
        valid = niri_valid(kdl)
        if valid is not None:
            self.assertTrue(valid[0], valid[1])
            # and included after binds of the user's own on the same key: still valid (the later one wins)
            import tempfile
            with tempfile.TemporaryDirectory() as d:
                (Path(d) / "rutile.kdl").write_text(kdl)
                both = niri_valid('binds {\n    Mod+Alt+L { spawn "foot"; }\n}\n' + f'include "{d}/rutile.kdl"\n')
            self.assertTrue(both[0], both[1])
        got, _ = module('{ enable = true; niri.binds = { enable = true; keys = { "Mod+X" = [ "power" "toggle" ]; }; }; }', niri=True)
        self.assertIn("Mod+X", got["included"])
        self.assertNotIn("XF86", got["included"], "your keys replace the defaults")

    def test_theming_sets_up_gtk_qt_kde_and_fonts(self):
        got, err = module("{ enable = true; theming.enable = true; }")
        self.assertIsNotNone(got, err)
        gtk, qt = got["gtk"], got["qt"]
        self.assertEqual(gtk["colorScheme"], "dark")
        self.assertEqual(gtk["theme"]["name"], "adw-gtk3-dark", "GTK 3 through the named colors the shell overrides")
        self.assertIsNone(gtk["gtk4"]["theme"], "libadwaita keeps its own (adw-gtk3's over it broke the accent)")
        self.assertEqual(gtk["gtk4"]["extraCss"], '@import url("file:///home/test/.config/gtk-4.0/rutile.css");')
        self.assertEqual(gtk["font"]["name"], "Google Sans Flex")
        self.assertEqual(qt["platformTheme"]["name"], "qtct")
        q6 = qt["kde"]["settings"]["qt6ct/qt6ct.conf"]
        self.assertEqual(q6["Appearance"]["style"], "Fusion")
        self.assertEqual(q6["Fonts"]["general"], '"Google Sans Flex,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"',
                         "quoted: QSettings reads an unquoted comma as a list")
        self.assertEqual(qt["kde"]["settings"]["qt5ct/qt5ct.conf"]["Fonts"]["general"], '"Google Sans Flex,11,-1,5,50,0,0,0,0,0"',
                         "Qt 5's format")
        kg = qt["kde"]["settings"]["kdeglobals"]
        self.assertEqual(kg["General"]["font"], "Google Sans Flex,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1", "KConfig: not quoted")
        self.assertEqual(kg["Icons"]["Theme"], "breeze-dark", "Adwaita's icons are dark on dark in Qt apps")
        self.assertEqual(q6["Appearance"]["icon_theme"], "breeze-dark")
        self.assertEqual(gtk["iconTheme"]["name"], "Adwaita")
        self.assertEqual(got["fonts"]["fontconfig"]["defaultFonts"]["sansSerif"], ["Google Sans Flex"])
        self.assertEqual({k: v for k, v in got["managed"].items() if v is not None},
                         {"enabled": True, "gtk": True, "qt": True, "kde": True}, "the shell's switches on")
        self.assertIn("rutile/managed.json", got["files"])

    def test_theming_parts_and_off(self):
        got, _ = module("{ enable = true; }")
        self.assertEqual(got["gtk"], {}, "off by default: nothing of the user's GTK or Qt touched")
        self.assertEqual(got["qt"], {})
        self.assertEqual(got["fonts"], {})
        got, _ = module("{ enable = true; theming = { enable = true; qt.enable = false; kde.enable = false; fonts.enable = false; }; }")
        self.assertEqual(got["qt"], {})
        self.assertNotIn("font", got["gtk"])
        self.assertEqual(got["fonts"], {})
        self.assertEqual({k: v for k, v in got["managed"].items() if v is not None}, {"enabled": True, "gtk": True})
        got, _ = module("{ enable = true; theming = { enable = true; gtk.plainGtk4 = true; }; }")
        self.assertEqual(got["gtk"]["gtk4"]["theme"]["name"], "adw-gtk3-dark")
        got, _ = module("{ enable = true; theming.enable = true; settings.appColors.kde = false; }")
        self.assertFalse(got["managed"]["kde"], "a switch set by hand wins")

    def test_settings_work_without_enable(self):
        got, _ = module("{ settings.motion.speed = 2; }")
        self.assertEqual(got["files"], ["rutile/managed.json"])
        self.assertEqual(got["packages"], [])


if __name__ == "__main__":
    unittest.main()
