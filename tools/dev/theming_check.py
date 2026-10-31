#!/usr/bin/env python3
"""Check that apps really wear the shell's look through programs.rutile.theming (D59), end to end, in a sandbox:

1. build a home-manager generation (tools/dev/theming-home.nix: home-manager's real gtk, qt, fontconfig modules)
   for a user whose home is a temporary folder, and lay its files out there as activation would (links, the
   profile, the kwriteconfig6 lines; nothing else of activation runs, so nothing reaches the real user);
2. run the packaged shell from that profile under a headless sway with a private bus, until it has written the
   gtk, qt and kde colors (no wallpaper: the shell's own colors, D58);
3. open a GTK 4 app, a libadwaita app, a GTK 3 app, Qt 6 and Qt 5 apps and KDE apps (kcalc, Dolphin, Kate) one at
   a time, screenshot each
   (grim), and check that its most common color is one of the shell's; then the same with theming off, to show the
   difference. Fonts: fontconfig's sans-serif and GTK's font setting.

    tools/dev/theming_check.py [--home-manager /nix/store/...-source] [--out DIR]    (make theming-check)
    RUTILE_PLAIN_GTK4=0 ...: with programs.rutile.theming.gtk.plainGtk4 off (plain GTK 4 apps not expected to match)

Not covered: GTK and libadwaita take theme, font, icons and the dark preference from GSettings (dconf, which
home-manager writes) or the settings portal; here the same keys go through GSettings' keyfile backend, and there is
no portal. The SVG image loader comes from librsvg, as NixOS sets it up system-wide. Live reload is not checked:
each app starts after the colors are written.
"""
import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import qtws  # noqa: E402

# (name, nixpkgs attribute, program, args)
APPS = [
    ("gtk4", "gtk4.dev", "gtk4-print-editor", []),     # the widget factory needs GStreamer
    ("libadwaita", "gnome-calculator", "gnome-calculator", []),
    ("gtk3", "gtk3.dev", "gtk3-widget-factory", []),
    ("qt6", "qt6Packages.qt6ct", "qt6ct", []),
    ("kde", "kdePackages.kcalc", "kcalc", []),
    ("dolphin", "kdePackages.dolphin", "dolphin", []),
    ("kate", "kdePackages.kate", "kate", []),
    ("qt5", "libsForQt5.qt5ct", "qt5ct", []),            # Qt 5: qt5ct's own window
]


def nix_out(attr):
    r = subprocess.run(["nix", "build", "--inputs-from", str(ROOT), f"nixpkgs#{attr}", "--no-link", "--print-out-paths"],
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0:
        raise RuntimeError(f"nix build nixpkgs#{attr}: {r.stderr[-500:]}")
    return r.stdout.split()[0]


def generation(home_manager, home, theming):
    r = subprocess.run(["nix-build", str(ROOT / "tools/dev/theming-home.nix"), "--arg", "homeManager", home_manager,
                        "--argstr", "home", str(home), "--arg", "theming", "true" if theming else "false",
                        "--arg", "plainGtk4", "false" if os.environ.get("RUTILE_PLAIN_GTK4") == "0" else "true",
                        "--no-out-link"], capture_output=True, text=True, timeout=1800, cwd=ROOT)
    if r.returncode != 0:
        raise RuntimeError("home-manager generation: " + r.stderr[-1500:])
    return Path(r.stdout.strip().splitlines()[-1])


def lay_out(gen, home):
    """What activation would leave in HOME, minus everything outside it: the files as links, the profile, and the
    kwriteconfig6 lines (programs.rutile.theming's fonts and qt5ct/qt6ct settings)."""
    files = gen / "home-files"
    for src in files.rglob("*"):
        if src.is_dir() and not src.is_symlink():
            continue
        dst = home / src.relative_to(files)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.symlink_to(src.resolve())
    (home / ".nix-profile").symlink_to(gen / "home-path")
    for line in (gen / "activate").read_text().splitlines():
        m = re.match(r"\s*run (\S+/kwriteconfig6 .*)$", line)
        if m:
            subprocess.run(["bash", "-c", m.group(1)], check=True, env=dict(os.environ, HOME=str(home)))
        # dconf: the same keys through GSettings' keyfile backend (GSETTINGS_BACKEND=keyfile), not the user's dconf
        m = re.search(r"dconf load / < (\S+)$", line)
        if m:
            keyfile = home / ".config/glib-2.0/settings/keyfile"
            keyfile.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(m.group(1), keyfile)
            keyfile.chmod(0o644)


def session_env(gen, home):
    """hm-session-vars.sh as a login shell would have it."""
    r = subprocess.run(["bash", "-c", f'unset __HM_SESS_VARS_SOURCED; . "{gen}/home-path/etc/profile.d/hm-session-vars.sh"; env -0'],
                       capture_output=True, text=True, env={"HOME": str(home), "PATH": os.environ["PATH"]})
    out = dict(kv.split("=", 1) for kv in r.stdout.split("\0") if "=" in kv)
    return {k: v for k, v in out.items() if k not in ("PATH", "HOME", "PWD", "SHLVL", "_")}


class BareBus:
    """A session bus that starts no services: a default session bus would start the system's portal, which reads
    the real user's settings (dconf) and hands them to the apps."""

    def __init__(self, root):
        self.conf = root / "bus.conf"
        self.conf.write_text('<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" '
                             '"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">\n<busconfig><type>session</type>'
                             f'<listen>unix:dir={root}</listen><policy context="default"><allow send_destination="*"/>'
                             '<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>\n')

    def __enter__(self):
        self.proc = subprocess.Popen(["dbus-daemon", f"--config-file={self.conf}", "--nofork", "--print-address=1"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.address = self.proc.stdout.readline().strip()
        return self

    def __exit__(self, *exc):
        self.proc.terminate()
        self.proc.wait(5)
        self.proc.stdout.close()


def read_ppm(path):
    data = path.read_bytes()
    parts = data.split(maxsplit=4)
    assert parts[0] == b"P6", parts[0]
    w, h = int(parts[1]), int(parts[2])
    pixels = parts[4]
    return w, h, pixels


def common_colors(path, n=3):
    w, h, px = read_ppm(path)
    counts = collections.Counter(px[i:i + 3] for i in range(0, w * h * 3, 3))
    return [("#%02x%02x%02x" % tuple(c), k / (w * h)) for c, k in counts.most_common(n)]


def distance(a, b):
    return max(abs(int(a[i:i + 2], 16) - int(b[i:i + 2], 16)) for i in (1, 3, 5))


def shell_colors(home):
    """Every color the shell wrote for these apps."""
    out = set()
    for f in [home / ".config/gtk-4.0/rutile.css", home / ".config/qt6ct/colors/rutile.conf"]:
        if f.exists():
            out |= {"#" + c.lower() for c in re.findall(r"#(?:ff)?([0-9a-fA-F]{6})\b", f.read_text())}
    kg = home / ".config/kdeglobals"
    if kg.exists():
        out |= {"#%02x%02x%02x" % tuple(map(int, m)) for m in re.findall(r"=(\d+),(\d+),(\d+)$", kg.read_text(), re.M)}
    return out


def run(home_manager, theming, out_dir, programs):
    root = Path(tempfile.mkdtemp(prefix="rutile-theming-"))
    home = root / "home"
    home.mkdir()
    report = {"theming": theming, "apps": {}}
    try:
        gen = generation(home_manager, home, theming)
        lay_out(gen, home)
        qtws.no_polkit_agent(home / ".config")
        hm = session_env(gen, home)
        with qtws.HeadlessSway(1024, 700) as comp, BareBus(root) as bus:
            base = comp.env({"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
                             "XDG_CACHE_HOME": str(home / ".cache"), "XDG_DATA_HOME": str(home / ".local/share"),
                             "XDG_STATE_HOME": str(home / ".local/state"), "DBUS_SESSION_BUS_ADDRESS": bus.address,
                             "XDG_SESSION_ID": "", "XDG_CURRENT_DESKTOP": "niri", "GDK_BACKEND": "wayland",
                             "XDG_DATA_DIRS": ":".join([f"{home}/.nix-profile/share", *programs["schemas"],
                                                        "/run/current-system/sw/share"]),
                             "GSETTINGS_BACKEND": "keyfile",
                             "GDK_PIXBUF_MODULE_FILE": f"{programs['librsvg']}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"})
            base.pop("QT_QPA_PLATFORMTHEME", None)
            base.pop("QT_STYLE_OVERRIDE", None)
            env = dict(base, **hm)
            exe = str(gen / "home-path/bin/rutile-shell")
            shell_log = open(root / "shell.log", "w")
            shell = subprocess.Popen([exe], env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            state = {}
            try:
                for _ in range(300):
                    r = subprocess.run([exe, "appcolors", "state"], env=env, capture_output=True, text=True, timeout=10)
                    try:
                        state = json.loads(r.stdout)
                    except ValueError:
                        state = {}
                    want = {"gtk", "qt", "kde"} if theming else set()
                    if set(state.get("synced", [])) >= want and state.get("runs", 0) >= (1 if theming else 0):
                        break
                    time.sleep(0.2)
            finally:
                shell.terminate()
                shell.wait(10)
                shell_log.close()
            report["appcolors"] = state
            report["fc-match sans-serif"] = subprocess.run(["fc-match", "sans-serif"], env=env, capture_output=True,
                                                           text=True).stdout.strip()
            q = subprocess.run([str(Path(programs["gtk4"]) / "bin/gtk4-query-settings")], env=env,
                               capture_output=True, text=True).stdout
            report["gtk4 settings"] = {k: v.strip('"') for k, v in re.findall(r"(gtk-(?:font|theme|icon-theme)-name):\s*(.*)", q)}
            palette = shell_colors(home)
            report["shell colors"] = len(palette)
            for name, attr, prog, args in APPS:
                app_env = dict(env, QT_QPA_PLATFORM="wayland")
                log = open(root / f"{name}.log", "w")
                p = subprocess.Popen([str(Path(programs[name]) / "bin" / prog), *args], env=app_env,
                                     stdout=log, stderr=subprocess.STDOUT)
                rect = None
                for _ in range(100):
                    tree = comp.msg("-t", "get_tree")
                    views = []

                    def walk(n):
                        if n.get("pid") and n.get("visible"):
                            views.append(n)
                        for c in n.get("nodes", []) + n.get("floating_nodes", []):
                            walk(c)
                    walk(tree or {})
                    if views:
                        rect = views[0]["rect"]
                        break
                    time.sleep(0.1)
                time.sleep(2.5)            # first frames, fonts, icons
                shot = out_dir / f"{name}-{'on' if theming else 'off'}.ppm"
                if rect:
                    subprocess.run(["grim", "-t", "ppm", "-g",
                                    f"{rect['x']},{rect['y']} {rect['width']}x{rect['height']}", str(shot)],
                                   env=comp.env(), check=True, timeout=20)
                    colors = common_colors(shot)
                    top = colors[0][0]
                    near = min((distance(top, c), c) for c in palette) if palette else (999, None)
                    report["apps"][name] = {"common": colors, "matches": near[0] <= 3, "nearest": near[1]}
                    try:
                        from PIL import Image
                        Image.open(shot).save(shot.with_suffix(".png"))
                        shot.unlink()
                    except ImportError:
                        pass
                else:
                    report["apps"][name] = {"error": "no window: " + (root / f"{name}.log").read_text()[-300:]}
                p.terminate()
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    p.kill()
                log.close()
                time.sleep(0.5)
        keep = out_dir / ("on" if theming else "off")
        keep.mkdir(exist_ok=True)
        for f in [*root.glob("*.log"), home / ".config/kdeglobals", home / ".config/qt6ct/qt6ct.conf",
                  home / ".config/gtk-3.0/gtk.css", home / ".config/glib-2.0/settings/keyfile"]:
            if f.exists():
                shutil.copy(f, keep / f.name)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--home-manager", help="home-manager's source (a store path or checkout); default: GitHub's")
    ap.add_argument("--out", default=None, help="folder for the screenshots (default: a temporary one)")
    a = ap.parse_args()
    for tool in ("sway", "swaymsg", "grim", "nix", "nix-build", "fc-match", "dbus-daemon"):
        if not shutil.which(tool):
            print(f"theming check: SKIPPED (needs {tool})")
            return 0
    if not a.home_manager:
        r = subprocess.run(["nix", "flake", "prefetch", "--json", "github:nix-community/home-manager"],
                           capture_output=True, text=True, timeout=600)
        a.home_manager = json.loads(r.stdout)["storePath"]
    out_dir = Path(a.out or tempfile.mkdtemp(prefix="rutile-theming-shots-"))
    out_dir.mkdir(parents=True, exist_ok=True)
    programs = {name: nix_out(attr) for name, attr, _, _ in APPS}
    programs["librsvg"] = nix_out("librsvg")
    # GSettings' schemas for the settings query tool (the apps' wrappers bring their own), as NixOS has them
    programs["schemas"] = [str(p) for p in (Path(nix_out("gsettings-desktop-schemas")) / "share/gsettings-schemas").iterdir()]
    on = run(a.home_manager, True, out_dir, programs)
    off = run(a.home_manager, False, out_dir, programs)
    problems = []
    if on["appcolors"].get("error"):
        problems.append(f"the shell: {on['appcolors']['error']}")
    if "Google Sans Flex" not in on["fc-match sans-serif"]:
        problems.append(f"fontconfig's sans-serif is {on['fc-match sans-serif']!r}")
    if not on["gtk4 settings"].get("gtk-font-name", "").startswith("Google Sans Flex"):
        problems.append(f"GTK's font is {on['gtk4 settings']}")
    plain = os.environ.get("RUTILE_PLAIN_GTK4") != "0"
    for name, _, _, _ in APPS:
        got, before = on["apps"].get(name, {}), off["apps"].get(name, {})
        if name == "gtk4" and not plain:
            # GTK's own theme has fixed colors: themed only with programs.rutile.theming.gtk.plainGtk4
            print(f"{name:11} (not themed without plainGtk4) on: {got.get('common', got)}")
            continue
        if "error" in got:
            problems.append(f"{name}: {got['error']}")
        elif not got["matches"]:
            problems.append(f"{name}: its main color {got['common'][0][0]} is none of the shell's (nearest {got['nearest']})")
        elif before.get("common") and before["common"][0][0] == got["common"][0][0]:
            problems.append(f"{name}: the same main color with theming off ({got['common'][0][0]})")
        print(f"{name:11} on: {got.get('common', got)}  off: {before.get('common', before)}")
    print("fonts:", on["fc-match sans-serif"], on["gtk4 settings"])
    print("screenshots:", out_dir)
    for p in problems:
        print("PROBLEM:", p)
    print("theming check: " + ("failed" if problems else "passed"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
