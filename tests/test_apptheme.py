"""tools/apptheme.py and tools/pywalfox_host.py (D52), always in a sandbox: HOME and the XDG directories point at a
temporary directory, so nothing here ever touches the real user's configuration."""
import json
import os
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools" / "apptheme.py"
HOST = ROOT / "tools" / "pywalfox_host.py"
FIXTURE = ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json"
sys.path.insert(0, str(ROOT / "tools"))
import pywalfox_host  # noqa: E402


@unittest.skipUnless(shutil.which("matugen"), "matugen not installed; app theming SKIPPED")
class AppTheme(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="rutile-apptheme-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config = self.home / "config"
        self.bin = self.home / "bin"
        self.bin.mkdir()
        # a pkill that only logs, so no real app gets a signal
        (self.bin / "pkill").write_text(f"#!/bin/sh\necho \"$@\" >> '{self.home}/pkill.log'\n")
        (self.bin / "pkill").chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_CACHE_HOME=str(self.home / "cache"), XDG_STATE_HOME=str(self.home / "state"),
                        XDG_DATA_HOME=str(self.home / "data"), PATH=f"{self.bin}:{os.environ['PATH']}")
        self.palette = json.loads(FIXTURE.read_text())
        self.primary = self.palette["colors"][self.palette["mode"]]["primary"]

    def sync(self, *apps, ok=True):
        r = subprocess.run([sys.executable, str(TOOL), "sync", "--palette", str(FIXTURE), "--apps", ",".join(apps)],
                           env=self.env, capture_output=True, text=True, timeout=60)
        if ok:
            self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def put(self, rel, text):
        p = self.config / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def signals(self):
        log = self.home / "pkill.log"
        return log.read_text().splitlines() if log.exists() else []

    def test_nothing_listed_touches_nothing(self):
        self.sync()
        self.assertFalse(self.config.exists())
        self.assertFalse((self.home / ".mozilla").exists())
        self.assertEqual(self.signals(), [])

    def test_gtk_imports_after_others_and_undoes_exactly(self):
        original = "@import 'noctalia.css';\n\nwindow { margin: 0; }\n"
        css3 = self.put("gtk-3.0/gtk.css", original)
        self.sync("gtk")
        rows = css3.read_text().splitlines()
        self.assertEqual(rows[0], "@import 'noctalia.css';", "theirs stays first")
        self.assertEqual(rows[1:4], ["/* >>> rutile colors >>> */", "@import 'rutile.css';",
                                     "/* <<< rutile colors <<< */"], "ours after it, before any rule, so ours wins")
        self.assertIn("window { margin: 0; }", rows)
        ours = (self.config / "gtk-3.0" / "rutile.css").read_text()
        self.assertIn(f"@define-color accent_bg_color {self.primary};", ours, "the shell's own primary")
        gtk4 = self.config / "gtk-4.0" / "gtk.css"
        self.assertEqual(gtk4.read_text().splitlines()[1], "@import 'rutile.css';", "made when missing")
        before = css3.stat().st_mtime_ns
        self.sync("gtk")
        self.assertEqual(css3.stat().st_mtime_ns, before, "a second sync writes nothing")
        self.assertEqual(css3.read_text().count("rutile.css"), 1)
        self.sync()
        self.assertEqual(css3.read_text(), original, "turned off: exactly as it was")
        self.assertFalse((self.config / "gtk-3.0" / "rutile.css").exists())
        self.assertFalse(gtk4.exists(), "the gtk.css it made, holding only its block, goes")

    def test_kitty_block_at_the_end_and_reload(self):
        original = "font_size 12\ninclude theme.conf\n"
        conf = self.put("kitty/kitty.conf", original)
        self.sync("kitty")
        self.assertTrue(conf.read_text().startswith(original))
        self.assertTrue(conf.read_text().rstrip().endswith("include rutile-colors.conf\n# <<< rutile colors <<<"))
        self.assertIn(f"cursor {self.primary}", (self.config / "kitty" / "rutile-colors.conf").read_text())
        self.assertEqual(len(self.signals()), 1)
        self.assertTrue(self.signals()[0].startswith("-USR1 -f"), "kitty reloads on SIGUSR1")
        self.sync("kitty")
        self.assertEqual(len(self.signals()), 1, "nothing changed: no signal")
        self.sync()
        self.assertEqual(conf.read_text(), original)
        self.assertEqual(len(self.signals()), 2, "turned off: it reloads its own colors")

    def test_btop_key_comes_back_unless_changed_since(self):
        conf = self.put("btop/btop.conf", '#? Config file for btop\ncolor_theme = "Default"\nupdate_ms = 2000\n')
        self.sync("btop")
        self.sync("btop")                       # again: theirs is still the one remembered, not ours
        self.assertIn('color_theme = "rutile"', conf.read_text())
        self.assertNotIn('"Default"', conf.read_text())
        self.assertTrue((self.config / "btop" / "themes" / "rutile.theme").exists())
        self.sync()
        self.assertIn('color_theme = "Default"', conf.read_text(), "theirs again")
        self.assertIn("update_ms = 2000", conf.read_text())
        self.sync("btop")
        conf.write_text(conf.read_text().replace('"rutile"', '"nord"'))
        self.sync()
        self.assertIn('color_theme = "nord"', conf.read_text(), "changed by the user since: left alone")

    def test_qt_keys_in_their_section(self):
        conf = self.put("qt6ct/qt6ct.conf", "[Appearance]\nstyle=Fusion\ncustom_palette=false\n\n[Fonts]\nfixed=x\n")
        self.sync("qt")
        text = conf.read_text()
        self.assertIn("custom_palette=true", text)
        self.assertIn(f"color_scheme_path={self.config / 'qt6ct' / 'colors' / 'rutile.conf'}", text)
        self.assertLess(text.index("color_scheme_path"), text.index("[Fonts]"), "in [Appearance]")
        scheme = (self.config / "qt6ct" / "colors" / "rutile.conf").read_text()
        self.assertIn("#ff" + self.primary[1:], scheme)
        active = next(line for line in scheme.splitlines() if line.startswith("active_colors="))
        self.assertEqual(len(active.split("=", 1)[1].split(", ")), 22, "21 QPalette roles and the accent")
        qt5 = self.config / "qt5ct" / "qt5ct.conf"
        self.assertIn("[Appearance]\ncolor_scheme_path=", qt5.read_text(), "made when missing")
        self.sync()
        self.assertEqual(conf.read_text(), "[Appearance]\nstyle=Fusion\ncustom_palette=false\n\n[Fonts]\nfixed=x\n")
        self.assertNotIn("color_scheme_path", qt5.read_text(), "a key that was not there goes")

    def test_ghostty_nvim_and_switching_between_apps(self):
        self.sync("ghostty", "nvim")
        self.assertIn("theme = rutile", (self.config / "ghostty" / "config").read_text())
        self.assertIn(f"background = {self.palette['colors']['dark']['surface']}",
                      (self.config / "ghostty" / "themes" / "rutile").read_text())
        lua = (self.config / "nvim" / "colors" / "rutile.lua").read_text()
        self.assertIn(f'primary = "{self.primary}"', lua)
        self.assertIn('vim.o.background = "dark"', lua)
        self.sync("nvim")
        self.assertFalse((self.config / "ghostty" / "config").exists(), "ghostty off: its block (all of it) goes")
        self.assertTrue((self.config / "nvim" / "colors" / "rutile.lua").exists(), "nvim stays")
        state = json.loads((self.home / "state" / "rutile" / "apptheme.json").read_text())
        self.assertEqual(sorted(state["apps"]), ["nvim"])

    def test_firefox_host_manifest_keeps_theirs_aside(self):
        hosts = self.home / ".mozilla" / "native-messaging-hosts"
        hosts.mkdir(parents=True)
        theirs = '{"name": "pywalfox", "path": "/nix/store/x-noctalia/bin/noctalia"}\n'
        (hosts / "pywalfox.json").write_text(theirs)
        self.sync("firefox")
        manifest = json.loads((hosts / "pywalfox.json").read_text())
        self.assertEqual(manifest["allowed_extensions"], ["pywalfox@frewacom.org"])
        wrapper = Path(manifest["path"])
        self.assertEqual(wrapper, self.home / "data" / "rutile" / "pywalfox-host")
        self.assertTrue(os.access(wrapper, os.X_OK))
        self.assertIn(str(HOST), wrapper.read_text())
        colors = json.loads((self.home / "cache" / "rutile" / "pywalfox.json").read_text())
        self.assertEqual(colors["colors"]["color1"], self.primary)
        self.assertEqual(colors["mode"], "dark")
        self.sync("firefox")
        self.assertEqual((hosts / "pywalfox.json.rutile-backup").read_text(), theirs, "theirs kept once, not ours")
        self.sync()
        self.assertEqual((hosts / "pywalfox.json").read_text(), theirs, "theirs back")
        self.assertFalse(wrapper.exists())
        self.assertFalse((hosts / "pywalfox.json.rutile-backup").exists())

    def test_firefox_never_keeps_its_own_manifest_aside(self):
        self.sync("firefox")
        (self.home / "state" / "rutile" / "apptheme.json").unlink()      # what it did, forgotten
        self.sync("firefox")
        self.assertFalse((self.home / ".mozilla" / "native-messaging-hosts" / "pywalfox.json.rutile-backup").exists())

    def test_firefox_without_another_host(self):
        self.sync("firefox")
        self.sync()
        self.assertEqual(list((self.home / ".mozilla" / "native-messaging-hosts").iterdir()), [])

    def test_unknown_app_and_bad_palette(self):
        r = self.sync("emacs", ok=False)
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown apps: emacs", r.stderr)
        self.assertFalse(self.config.exists(), "nothing done")
        r = subprocess.run([sys.executable, str(TOOL), "sync", "--palette", str(self.home / "none.json"),
                            "--apps", "kitty"], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)

    def test_the_apps_list(self):
        r = subprocess.run([sys.executable, str(TOOL), "apps"], capture_output=True, text=True)
        self.assertEqual([line.split("\t")[0] for line in r.stdout.splitlines()],
                         ["gtk", "qt", "kitty", "ghostty", "btop", "nvim", "firefox"])


class PywalfoxHost(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="rutile-pywalfox-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.colors = self.dir / "rutile" / "pywalfox.json"
        self.colors.parent.mkdir()

    def write(self, first, mode="dark"):
        cols = {f"color{i}": f"#{i:02x}{i:02x}{i:02x}" for i in range(16)}
        cols["color0"] = first
        self.colors.write_text(json.dumps({"wallpaper": "", "mode": mode, "colors": cols}))

    def test_replies(self):
        self.assertEqual(pywalfox_host.handle({"action": "debug:version"}),
                         [{"action": "debug:version", "success": True, "data": "2.9.0"}])
        self.write("#111111", "light")
        replies = pywalfox_host.handle({"action": "action:colors"}, self.colors)
        self.assertEqual(replies[0]["data"]["colors"][0], "#111111")
        self.assertEqual(len(replies[0]["data"]["colors"]), 16)
        self.assertEqual(replies[1], {"action": "theme:mode", "success": True, "data": "light"})
        css = pywalfox_host.handle({"action": "css:enable", "target": "userChrome"}, self.colors)
        self.assertEqual(css[0]["success"], False)
        self.assertEqual(css[0]["data"], "userChrome")
        self.assertEqual(pywalfox_host.handle({"action": "nope"})[0]["action"], "action:invalid")
        missing = pywalfox_host.handle({"action": "action:colors"}, self.dir / "none.json")
        self.assertEqual(len(missing), 1)
        self.assertFalse(missing[0]["success"])
        self.assertIn("No colors from Rutile Shell yet", missing[0]["error"])

    def test_over_stdio_and_pushes_changes(self):
        self.write("#222222")
        env = dict(os.environ, XDG_CACHE_HOME=str(self.dir), RUTILE_PYWALFOX_POLL="0.05")
        proc = subprocess.Popen([sys.executable, str(HOST)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env,
                                bufsize=0)          # unbuffered: select() then sees every byte not yet read
        self.addCleanup(proc.stdout.close)
        self.addCleanup(proc.kill)

        def ask(message):
            body = json.dumps(message).encode()
            proc.stdin.write(struct.pack("@I", len(body)) + body)
            proc.stdin.flush()

        def exactly(n, timeout):
            data = b""
            while len(data) < n:
                ready, _, _ = select.select([proc.stdout], [], [], timeout)
                self.assertTrue(ready, "the host sent nothing")
                chunk = proc.stdout.read(n - len(data))
                self.assertTrue(chunk, "the host closed its output")
                data += chunk
            return data

        def read(timeout=5):
            (n,) = struct.unpack("@I", exactly(4, timeout))
            return json.loads(exactly(n, timeout))

        ask({"action": "debug:version"})
        self.assertEqual(read()["data"], "2.9.0")
        ask({"action": "action:colors"})
        self.assertEqual(read()["data"]["colors"][0], "#222222")
        self.assertEqual(read()["data"], "dark")
        time.sleep(0.1)
        self.write("#333333")
        pushed = read()
        self.assertEqual((pushed["action"], pushed["data"]["colors"][0]), ("action:colors", "#333333"),
                         "a new palette reaches Firefox without being asked")
        self.assertEqual(read()["action"], "theme:mode")
        proc.stdin.close()
        self.assertEqual(proc.wait(timeout=5), 0, "Firefox closing stdin ends it")


if __name__ == "__main__":
    unittest.main()
