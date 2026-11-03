"""The `rutile-shell` command (bin/rutile-shell, plan 6.1): its help lists exactly the IPC targets and functions that
shell/shell.qml's IpcHandlers answer, with their arguments, and each form of the command reaches Quickshell with
the right arguments (a stand-in quickshell prints what it got). `flatpak-theming` (D66) against a stand-in flatpak
that logs its calls."""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "rutile-shell"
SHELL_QML = ROOT / "shell" / "shell.qml"


def handlers():
    """{target: {function: number of arguments}} from shell.qml's IpcHandlers."""
    out = {}
    text = SHELL_QML.read_text()
    for block in re.finditer(r"IpcHandler \{(.*?)\n    \}", text, re.S):
        target = re.search(r'target: "(\w+)"', block.group(1)).group(1)
        out[target] = {name: len([a for a in args.split(",") if a.strip()])
                       for name, args in re.findall(r"\n        function (\w+)\(([^)]*)\)", block.group(1))}
    return out


def help_reference(text):
    """{target: {function: number of arguments}} from the help's IPC section. A line is `target  entries` or
    `  entries`; entries are `fn ARG...` alternatives split by `|`, before two spaces and a description."""
    out = {}
    section = text.split("\nIPC", 1)[1].split("\nExamples:", 1)[0]
    target = None
    for line in section.splitlines()[1:]:
        if not line.strip():
            continue
        m = re.match(r"  (\w+)\s+(.*)", line)
        if m and not line.startswith("   "):
            target, rest = m.group(1), m.group(2)
        elif line.startswith(" " * 17) and line[17] != " ":
            rest = line[17:]
        else:
            continue          # a description's second line
        entries = re.split(r"\s{2,}", rest.strip())[0]
        for alt in entries.split(" | "):
            words = alt.split()
            out.setdefault(target, {})[words[0]] = len(words) - 1
    return out


def run(*args, env=None):
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / "quickshell"
        fake.write_text('#!/bin/sh\nfor a do printf "[%s]" "$a"; done\necho\n')
        fake.chmod(0o755)
        e = dict(os.environ, RUTILE_QUICKSHELL=str(fake), RUTILE_SHELL_QML="/s/shell.qml", **(env or {}))
        return subprocess.run([str(CLI), *args], capture_output=True, text=True, env=e, timeout=10)


class Help(unittest.TestCase):
    def test_lists_every_ipc_function_and_nothing_else(self):
        real = handlers()
        self.assertGreater(len(real), 10, "the parser found the handlers")
        self.assertIn("setSpeed", real["motion"])
        self.assertEqual(real["notifications"]["invoke"], 2)
        r = run("--help")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(help_reference(r.stdout), real)

    def test_targets_list_matches(self):
        text = CLI.read_text()
        targets = re.search(r'^TARGETS="([^"]*)"', text, re.M).group(1).split()
        self.assertEqual(sorted(targets), sorted(handlers()))

    def test_help_forms(self):
        for form in ("-h", "--help", "help"):
            r = run(form)
            self.assertEqual(r.returncode, 0)
            self.assertIn("rutile-shell TARGET FUNCTION", r.stdout)
            self.assertNotIn("[", r.stdout.splitlines()[0][:1], "quickshell was not called")


class Forwarding(unittest.TestCase):
    def check(self, args, expected):
        r = run(*args)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "".join(f"[{a}]" for a in expected))

    def test_run(self):
        self.check([], ["-p", "/s/shell.qml"])
        self.check(["run", "-d"], ["-p", "/s/shell.qml", "-d"])
        self.check(["-d"], ["-p", "/s/shell.qml", "-d"])

    def test_target_calls(self):
        self.check(["lock", "lock"], ["ipc", "-p", "/s/shell.qml", "call", "lock", "lock"])
        self.check(["toast", "send", "two words", ""],
                   ["ipc", "-p", "/s/shell.qml", "call", "toast", "send", "two words", ""])
        # a widget preview gets a full path from a relative one
        r = run("widgets", "preview", "w.json")
        self.assertIn(f"[preview][{os.getcwd()}/w.json]", r.stdout)
        self.check(["widgets", "preview", "/a/w.json"], ["ipc", "-p", "/s/shell.qml", "call", "widgets", "preview", "/a/w.json"])
        # and so does a widget put on the desktop (D81)
        r = run("widgets", "add", "w.json")
        self.assertIn(f"[add][{os.getcwd()}/w.json]", r.stdout)
        self.check(["widgets", "edit"], ["ipc", "-p", "/s/shell.qml", "call", "widgets", "edit"])
        # the Settings app's desktop file runs `rutile-shell settings`
        self.check(["settings"], ["ipc", "-p", "/s/shell.qml", "call", "settings", "open", ""])
        self.check(["settings", "openSetting", "security", "lock.idleMinutes"],
                   ["ipc", "-p", "/s/shell.qml", "call", "settings", "openSetting", "security", "lock.idleMinutes"])

    def test_ipc_passthrough(self):
        self.check(["ipc"], ["ipc", "-p", "/s/shell.qml", "show"])
        self.check(["ipc", "call", "osd", "volumeUp"], ["ipc", "-p", "/s/shell.qml", "call", "osd", "volumeUp"])

    def test_log_and_kill(self):
        self.check(["log", "-f"], ["log", "-p", "/s/shell.qml", "-f"])
        self.check(["kill"], ["kill", "-p", "/s/shell.qml"])

    def test_mistakes(self):
        r = run("lock")
        self.assertEqual(r.returncode, 2)
        self.assertIn("needs a function", r.stderr)
        self.assertEqual(r.stdout, "")
        r = run("lokc", "lock")
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown command 'lokc'", r.stderr)
        self.assertEqual(r.stdout, "")

    def test_finds_the_checkout_without_the_variable(self):
        env = {k: v for k, v in os.environ.items() if k != "RUTILE_SHELL_QML"}
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "quickshell"
            fake.write_text('#!/bin/sh\nfor a do printf "[%s]" "$a"; done\necho\n')
            fake.chmod(0o755)
            env["RUTILE_QUICKSHELL"] = str(fake)
            r = subprocess.run([str(CLI), "kill"], capture_output=True, text=True, env=env, timeout=10)
        self.assertEqual(r.stdout.strip(), f"[kill][-p][{ROOT / 'bin' / '..' / 'shell' / 'shell.qml'}]")


FAKE_FLATPAK = """#!/bin/sh
printf '%s\\n' "$*" >> "$LOG"
case "$1" in
    list) printf 'org.freedesktop.Platform\\t25.08\\norg.kde.Platform\\t6.10\\norg.kde.Platform\\t5.15-24.08\\n'
          printf 'org.kde.Platform\\t6.10\\norg.kde.Platform\\t6.2\\n' ;;
    remote-info) case "$*" in *//6.2*) exit 1 ;; esac ;;
    install) [ -n "${FAIL_INSTALL-}" ] && exit 1 ;;
esac
exit 0
"""


class FlatpakTheming(unittest.TestCase):
    def run_it(self, *args, path_extra=(), env=None):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            for name, text in (("flatpak", FAKE_FLATPAK), *path_extra):
                (bindir / name).write_text(text)
                (bindir / name).chmod(0o755)
            log = Path(tmp) / "log"
            log.touch()
            # only the stand-ins and what the script itself needs
            tools = Path(tmp) / "tools"
            tools.mkdir()
            for t in ("sh", "sort", "readlink", "printf", "cat", "dirname", "basename"):
                real = subprocess.run(["sh", "-c", f"command -v {t}"], capture_output=True, text=True).stdout.strip()
                if real.startswith("/"):
                    (tools / t).symlink_to(real)
            e = {"PATH": f"{bindir}:{tools}", "LOG": str(log), "HOME": tmp, **(env or {})}
            r = subprocess.run(["sh", str(CLI), "flatpak-theming", *args], capture_output=True, text=True, env=e,
                               timeout=10, stdin=subprocess.DEVNULL)
            return r, log.read_text().splitlines()

    def test_installs_and_overrides(self):
        r, calls = self.run_it("-y")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(calls[0], "remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo")
        install = [c for c in calls if c.startswith("install")]
        self.assertEqual(install, ["install --user --or-update -y flathub org.gtk.Gtk3theme.adw-gtk3 "
                                   "org.gtk.Gtk3theme.adw-gtk3-dark org.kde.KStyle.Kvantum//5.15-24.08 "
                                   "org.kde.KStyle.Kvantum//6.10"], "one Kvantum per KDE runtime Flathub has it for")
        self.assertIn("no Kvantum for KDE runtime 6.2", r.stdout)
        override = [c for c in calls if c.startswith("override")]
        self.assertEqual(len(override), 1)
        for arg in ("--filesystem=xdg-config/gtk-3.0:ro", "--filesystem=xdg-config/gtk-4.0:ro",
                    "--filesystem=xdg-config/Kvantum:ro", "--filesystem=xdg-config/kdeglobals:ro",
                    "--env=QT_QPA_PLATFORMTHEME=kde", "--env=_JAVA_AWT_WM_NONREPARENTING=1"):
            self.assertIn(arg, override[0].split())
        self.assertEqual("--filesystem=/nix/store:ro" in override[0].split(), Path("/nix/store").is_dir())
        self.assertTrue(override[0].startswith("override --user "))

    def test_asks_without_y(self):
        r, calls = self.run_it()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("-y", [c for c in calls if c.startswith("install")][0].split())

    def test_a_failed_install_stops_before_the_overrides(self):
        r, calls = self.run_it("-y", env={"FAIL_INSTALL": "1"})
        self.assertEqual(r.returncode, 1)
        self.assertFalse([c for c in calls if c.startswith("override")])

    def test_without_flatpak(self):
        with tempfile.TemporaryDirectory() as tmp:
            for t in ("dirname", "readlink"):
                (Path(tmp) / t).symlink_to(shutil.which(t))
            r = subprocess.run([shutil.which("sh"), str(CLI), "flatpak-theming"], capture_output=True, text=True,
                               env={"PATH": tmp, "HOME": tmp}, timeout=10)
        self.assertEqual(r.returncode, 1)
        self.assertIn("flatpak is not installed", r.stderr)

    def test_terminal(self):
        # the first terminal found runs the command again with --pause; TERMINAL comes first, with -e
        echo = '#!/bin/sh\nprintf "[%s]" "$(basename "$0")" "$@" >> "$LOG"\n'
        r, calls = self.run_it("--terminal", path_extra=(("foot", echo), ("alacritty", echo)),
                               env={"RUTILE_CLI": "/p/rutile-shell"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(calls, ["[foot][/p/rutile-shell][flatpak-theming][--pause]"])
        r, calls = self.run_it("--terminal", path_extra=(("foot", echo), ("myterm", echo)),
                               env={"RUTILE_CLI": "/p/rutile-shell", "TERMINAL": "myterm"})
        self.assertEqual(calls, ["[myterm][-e][/p/rutile-shell][flatpak-theming][--pause]"])

    def test_no_terminal(self):
        r, calls = self.run_it("--terminal", env={"RUTILE_CLI": "/nonexistent/rutile-shell"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("no terminal found", r.stderr)

    def test_pause_waits_and_keeps_the_status(self):
        r, calls = self.run_it("--pause", env={"FAIL_INSTALL": "1"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("Not finished", r.stdout)
        self.assertIn("Press Enter to close", r.stdout)


class SettingsDesktopFile(unittest.TestCase):
    """The Settings app in app launchers: a desktop file running `rutile-shell settings`, which the package installs
    with its own CLI's full path."""
    def test_desktop_file(self):
        f = ROOT / "share" / "applications" / "rutile-settings.desktop"
        entry = dict(l.split("=", 1) for l in f.read_text().splitlines()[1:] if "=" in l)
        self.assertEqual(f.read_text().splitlines()[0], "[Desktop Entry]")
        self.assertEqual(entry["Type"], "Application")
        self.assertEqual(entry["Exec"], "rutile-shell settings")
        self.assertIn("Settings;", entry["Categories"])
        package = (ROOT / "nix" / "package.nix").read_text()
        self.assertIn("../share\n", package, "in the package's sources")
        self.assertIn("$out/share/applications/rutile-settings.desktop", package)
        self.assertIn('"Exec=$out/bin/rutile-shell "', package)


if __name__ == "__main__":
    unittest.main()
