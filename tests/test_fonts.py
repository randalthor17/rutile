import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import fontconf  # noqa: E402
import otinfo  # noqa: E402

FONTS = json.loads((ROOT / "theme" / "fonts.json").read_text())


def real_font(kind):
    return otinfo.find_font(FONTS[kind]["file"], otinfo.font_dirs())


def build_sfnt(names, axes, tables_extra=None):
    """A minimal sfnt with a name table and (optionally) an fvar table, for parser tests."""
    records, strings = [], b""
    for plat, enc, lang, nid, text in names:
        raw = text.encode("utf-16-be" if plat in (0, 3) else "mac_roman")
        records.append(struct.pack(">6H", plat, enc, lang, nid, len(raw), len(strings)))
        strings += raw
    name = struct.pack(">3H", 0, len(records), 6 + 12 * len(records)) + b"".join(records) + strings
    tables = {"name": name}
    if axes is not None:
        recs = b"".join(struct.pack(">4siiiHH", tag.encode(), int(lo * 65536), int(d * 65536), int(hi * 65536), 0, 256)
                        for tag, lo, d, hi in axes)
        tables["fvar"] = struct.pack(">6H2H", 1, 0, 16, 2, len(axes), 20, 0, 0)[:16] + recs
    tables.update(tables_extra or {})
    header = b"\x00\x01\x00\x00" + struct.pack(">HHHH", len(tables), 0, 0, 0)
    offset = 12 + 16 * len(tables)
    directory, body = b"", b""
    for tag, data in tables.items():
        directory += struct.pack(">4sIII", tag.encode(), 0, offset + len(body), len(data))
        body += data + b"\x00" * (-len(data) % 4)
    return header + directory + body


class FontsJson(unittest.TestCase):
    def test_shape(self):
        for kind in ("text", "icons"):
            f = FONTS[kind]
            self.assertTrue(f["family"] and f["file"].endswith(".ttf") and f["license"] and f["package"], kind)
            self.assertTrue(f["axes"], kind)
            for tag, a in f["axes"].items():
                self.assertEqual(len(tag), 4, tag)
                self.assertLessEqual(a["min"], a["default"], tag)
                self.assertLessEqual(a["default"], a["max"], tag)


class OtinfoParser(unittest.TestCase):
    def write(self, data):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        p = Path(d) / "f.ttf"
        p.write_bytes(data)
        return str(p)

    def test_reads_names_and_axes_including_negative_values(self):
        data = build_sfnt([(3, 1, 0x409, 1, "Test Family"), (3, 1, 0x409, 14, "https://example.org")],
                          [("wght", 100, 400, 900), ("slnt", -10, 0, 0)])
        info = otinfo.read(self.write(data))
        self.assertEqual(info["names"]["family"], "Test Family")
        self.assertEqual(info["names"]["license_url"], "https://example.org")
        self.assertEqual(info["axes"]["wght"], {"min": 100.0, "default": 400.0, "max": 900.0})
        self.assertEqual(info["axes"]["slnt"], {"min": -10.0, "default": 0.0, "max": 0.0})

    def test_prefers_windows_english_over_mac_names(self):
        data = build_sfnt([(1, 0, 0, 1, "Mac Name"), (3, 1, 0x409, 1, "Windows Name"), (3, 1, 0x407, 1, "German Name")], None)
        self.assertEqual(otinfo.read(self.write(data))["names"]["family"], "Windows Name")

    def test_static_font_has_no_axes(self):
        self.assertEqual(otinfo.read(self.write(build_sfnt([(3, 1, 0x409, 1, "Static")], None)))["axes"], {})

    def test_rejects_garbage_truncation_and_collections(self):
        for data, why in ((b"abc", "short"), (b"GARBAGEGARBAGEGARBAGE", "magic"), (b"ttcf" + b"\x00" * 20, "collection")):
            with self.assertRaises(otinfo.FontError, msg=why):
                otinfo.read(self.write(data))
        good = build_sfnt([(3, 1, 0x409, 1, "X")], [("wght", 1, 400, 1000)])
        with self.assertRaises(otinfo.FontError):
            otinfo.read(self.write(good[: len(good) - 8]))  # table runs past end of file
        with self.assertRaises(otinfo.FontError):
            otinfo.read(self.write(build_sfnt([], None, {"name": b"\x00\x00"})))  # name table too short

    def test_find_font_is_recursive_and_dirs_come_from_env(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        (d / "a" / "b").mkdir(parents=True)
        (d / "a" / "b" / "Wanted.ttf").write_bytes(b"x")
        self.assertEqual(otinfo.find_font("Wanted.ttf", ["/nonexistent", str(d)]), str(d / "a" / "b" / "Wanted.ttf"))
        self.assertIsNone(otinfo.find_font("Missing.ttf", [str(d)]))
        old = os.environ.get("RUTILE_FONT_DIRS")
        os.environ["RUTILE_FONT_DIRS"] = os.pathsep.join(["/x", "", "/y"])
        try:
            self.assertEqual(otinfo.font_dirs(), ["/x", "/y"])
        finally:
            if old is None:
                os.environ.pop("RUTILE_FONT_DIRS")
            else:
                os.environ["RUTILE_FONT_DIRS"] = old


class RealFonts(unittest.TestCase):
    """Checked against the actual font files when RUTILE_FONT_DIRS finds them (the dev shell sets it)."""

    def check(self, kind):
        path = real_font(kind)
        if not path:
            self.skipTest(f"{FONTS[kind]['file']} not found in RUTILE_FONT_DIRS; SKIPPED")
        info = otinfo.read(path)
        self.assertEqual(info["names"]["family"], FONTS[kind]["family"])
        self.assertEqual(set(info["axes"]), set(FONTS[kind]["axes"]))
        for tag, want in FONTS[kind]["axes"].items():
            got = info["axes"][tag]
            self.assertEqual((got["min"], got["default"], got["max"]), (want["min"], want["default"], want["max"]), tag)
        return info

    def test_text_font_matches_fonts_json(self):
        info = self.check("text")
        self.assertIn("SIL Open Font License", info["names"]["license"])

    def test_icon_font_matches_fonts_json(self):
        self.check("icons")


class NixPackage(unittest.TestCase):
    text = (ROOT / "nix" / "googlesans-flex.nix").read_text()

    def test_matches_fonts_json(self):
        self.assertIn(f'version = "{FONTS["text"]["version"]}"', self.text)
        self.assertIn("googlefonts/googlesans-flex", self.text)
        self.assertIn("licenses.ofl", self.text)
        self.assertIn("share/fonts/truetype", self.text)
        self.assertIn("*.ttf", self.text)

    def test_is_pinned_by_hash(self):
        self.assertRegex(self.text, r'hash = "sha256-[A-Za-z0-9+/]{43}="')


class FontconfWriter(unittest.TestCase):
    def tmp(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        return Path(d)

    def test_render_is_wellformed_with_include_first_and_dirs_in_order(self):
        root = ET.fromstring(fontconf.render(["/a/fonts", "/b/fonts"]))
        self.assertEqual(root.tag, "fontconfig")
        self.assertEqual([c.tag for c in root], ["include", "dir", "dir"])
        self.assertEqual(root[0].get("ignore_missing"), "yes")
        self.assertEqual(root[0].text, fontconf.SYSTEM_CONF)
        self.assertEqual([c.text for c in root[1:]], ["/a/fonts", "/b/fonts"])

    def test_render_escapes_special_characters(self):
        root = ET.fromstring(fontconf.render(["/odd & <dir>/fonts"], include=None))
        self.assertEqual([c.tag for c in root], ["dir"])
        self.assertEqual(root[0].text, "/odd & <dir>/fonts")

    def test_usable_dirs_filters_and_reports(self):
        d = self.tmp()
        msgs = []
        out = fontconf.usable_dirs(["relative/path", str(d / "missing"), str(d), str(d)], msgs.append)
        self.assertEqual(out, [str(d)])
        self.assertEqual(len(msgs), 2)

    def test_write_is_atomic_0644_and_leaves_no_temp_files(self):
        d = self.tmp()
        out = fontconf.write(d / "sub" / "fonts.conf", [str(d)])
        self.assertEqual(oct(out.stat().st_mode & 0o777), "0o644")
        self.assertEqual([p.name for p in out.parent.iterdir()], ["fonts.conf"])
        ET.parse(out)

    def test_default_out_follows_xdg_cache_home(self):
        old = os.environ.get("XDG_CACHE_HOME")
        os.environ["XDG_CACHE_HOME"] = "/tmp/xdg-test"
        try:
            self.assertEqual(str(fontconf.default_out()), "/tmp/xdg-test/rutile/fonts.conf")
        finally:
            if old is None:
                os.environ.pop("XDG_CACHE_HOME")
            else:
                os.environ["XDG_CACHE_HOME"] = old

    def run_cli(self, env_dirs, out):
        env = dict(os.environ, RUTILE_FONT_DIRS=env_dirs)
        return subprocess.run([sys.executable, str(ROOT / "tools" / "fontconf.py"), "write", "--out", str(out)],
                              capture_output=True, text=True, env=env)

    def test_cli_exit_codes(self):
        d = self.tmp()
        ok = self.run_cli(str(d), d / "ok.conf")
        self.assertEqual((ok.returncode, ok.stdout.strip()), (0, str(d / "ok.conf")))
        none = self.run_cli(os.pathsep.join(["", "/does/not/exist"]), d / "none.conf")
        self.assertEqual(none.returncode, 1)
        self.assertFalse((d / "none.conf").exists())

    @unittest.skipUnless(shutil.which("fc-match"), "fc-match not installed; SKIPPED")
    def test_fontconfig_resolves_the_font_through_the_generated_file(self):
        path = real_font("text")
        if not path:
            self.skipTest("text font not found in RUTILE_FONT_DIRS; SKIPPED")
        d = self.tmp()
        fonts = d / "fonts" / "truetype"
        fonts.mkdir(parents=True)
        shutil.copy(path, fonts / Path(path).name)
        conf = fontconf.write(d / "fonts.conf", [str(d / "fonts")])
        env = dict(os.environ, FONTCONFIG_FILE=str(conf), HOME=str(d), XDG_CACHE_HOME=str(d / "cache"))
        got = subprocess.run(["fc-match", "-f", "%{family}", FONTS["text"]["family"]],
                             capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(got.stdout.strip(), FONTS["text"]["family"], got.stderr)
        # and the system configuration is still in effect: a generic family still resolves
        other = subprocess.run(["fc-match", "-f", "%{family}", "sans-serif"], capture_output=True, text=True,
                               env=env, timeout=120)
        self.assertTrue(other.stdout.strip())


if __name__ == "__main__":
    unittest.main()
