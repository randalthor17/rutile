#!/usr/bin/env python3
"""Give other apps Rutile's colors (the settings' theme.apps.*, off by default; D52).

    apptheme.py sync --palette PATH [--apps gtk,kitty,...]
    apptheme.py apps

`sync` makes the listed apps (none: every app off) wear the palette, and takes Rutile's colors back out of every
app it themed before that is no longer listed. It runs matugen again from the palette's source color, scheme,
mode and contrast (palette.json records them), so the apps get exactly the shell's colors, with only the listed
apps' templates (theme/apps/). It only ever touches what it wrote: its own files, a marked block in a config it
includes from, or one key whose previous value it keeps; what it did is in $XDG_STATE_HOME/rutile/apptheme.json,
which is how `sync` knows what to undo. Apps that can reload are told to (kitty, Ghostty, btop: a signal); the
others pick the colors up when they start.

Firefox is themed through the Pywalfox extension with our own native-messaging host (tools/pywalfox_host.py),
so Pywalfox's own program is not needed: the host's manifest goes in ~/.mozilla/native-messaging-hosts (another
one there, Noctalia's, is kept aside and put back when Firefox is turned off).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "theme" / "apps"
HOME = Path(os.environ.get("HOME", str(Path.home())))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state") / "rutile" / "apptheme.json"
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "rutile"

BEGIN, END = ">>> rutile colors >>>", "<<< rutile colors <<<"


class ThemeError(Exception):
    pass


# ---- the apps: templates (template name, where it goes) and what else installs them ----

def gtk_css_line(version):
    return {"file": CONFIG / f"gtk-{version}.0" / "gtk.css", "comment": ("/* ", " */"),
            "lines": ["@import 'rutile.css';"], "where": "after-imports"}


APPS = {
    "gtk": {
        "title": "GTK 3 and 4",
        "files": [("gtk.css", CONFIG / "gtk-3.0" / "rutile.css"), ("gtk.css", CONFIG / "gtk-4.0" / "rutile.css")],
        "blocks": [gtk_css_line(3), gtk_css_line(4)],
    },
    "qt": {
        "title": "Qt (qt5ct, qt6ct)",
        "files": [("qtct.conf", CONFIG / "qt5ct" / "colors" / "rutile.conf"),
                  ("qtct.conf", CONFIG / "qt6ct" / "colors" / "rutile.conf")],
        "keys": [(CONFIG / v / f"{v}.conf", "Appearance", k, val)
                 for v in ("qt5ct", "qt6ct")
                 for k, val in (("color_scheme_path", str(CONFIG / v / "colors" / "rutile.conf")),
                                ("custom_palette", "true"))],
    },
    "kitty": {
        "title": "kitty",
        "files": [("kitty.conf", CONFIG / "kitty" / "rutile-colors.conf")],
        "blocks": [{"file": CONFIG / "kitty" / "kitty.conf", "comment": ("# ", ""),
                    "lines": ["include rutile-colors.conf"], "where": "end"}],
        "reload": ("USR1", r"(^|/)\.?kitty(-wrapped)?( |$)"),
    },
    "ghostty": {
        "title": "Ghostty",
        "files": [("ghostty", CONFIG / "ghostty" / "themes" / "rutile")],
        "blocks": [{"file": CONFIG / "ghostty" / "config", "comment": ("# ", ""),
                    "lines": ["theme = rutile"], "where": "end"}],
        "reload": ("USR2", r"(^|/)\.?ghostty(-wrapped)?( |$)"),
    },
    "btop": {
        "title": "btop",
        "files": [("btop.theme", CONFIG / "btop" / "themes" / "rutile.theme")],
        "keys": [(CONFIG / "btop" / "btop.conf", None, "color_theme", '"rutile"')],
        "reload": ("USR2", r"(^|/)\.?btop(-wrapped)?( |$)"),
    },
    "nvim": {
        "title": "Neovim (:colorscheme rutile)",
        "files": [("nvim.lua", CONFIG / "nvim" / "colors" / "rutile.lua")],
    },
    "firefox": {
        "title": "Firefox (Pywalfox)",
        "files": [("pywalfox.json", CACHE / "rutile" / "pywalfox.json")],
        "firefox": True,
    },
}


# ---- small file edits that can be undone ----

def write_if_changed(path, text):
    path = Path(path)
    if path.exists() and path.read_text() == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".rutile-", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    return True


def marker(comment, word):
    return f"{comment[0]}{word}{comment[1]}"


def strip_block(text, comment):
    """The text without our marked block (and nothing else)."""
    out, inside = [], False
    for line in text.splitlines(keepends=True):
        if line.rstrip("\n") == marker(comment, BEGIN):
            inside = True
            continue
        if inside and line.rstrip("\n") == marker(comment, END):
            inside = False
            continue
        if not inside:
            out.append(line)
    return "".join(out)


def add_block(path, comment, lines, where):
    path = Path(path)
    text = strip_block(path.read_text(), comment) if path.exists() else ""
    block = [marker(comment, BEGIN), *lines, marker(comment, END)]
    rows = text.splitlines()
    if where == "after-imports":
        # CSS: @import must come first; after the others, so ours wins over an earlier theme's
        i = 0
        while i < len(rows) and (rows[i].lstrip().startswith("@import") or rows[i].strip() == ""):
            i += 1
        while i > 0 and rows[i - 1].strip() == "":
            i -= 1
        rows[i:i] = block
    else:
        rows += block
    return write_if_changed(path, "\n".join(rows) + "\n")


def remove_block(path, comment):
    path = Path(path)
    if not path.exists():
        return False
    text = path.read_text()
    new = strip_block(text, comment)
    if new == text:
        return False
    if new.strip() == "":
        path.unlink()                    # we made it, it held only our block
        return True
    return write_if_changed(path, new)


def get_key(path, section, key):
    """The value of `key` (in [section], or before any section when None), or None."""
    path = Path(path)
    if not path.exists():
        return None
    current = None
    for line in path.read_text().splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            current = s[1:-1]
            continue
        if current == section and "=" in s and s.split("=", 1)[0].strip() == key:
            return s.split("=", 1)[1].strip()
    return None


def set_key(path, section, key, value):
    """Sets `key = value` keeping the rest of the file; value None removes the key."""
    path = Path(path)
    rows = path.read_text().splitlines() if path.exists() else []
    current, done, out = None, False, []
    section_at = None
    for line in rows:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            if current == section and not done and value is not None:
                out.append(f"{key}={value}" if section else f"{key} = {value}")
                done = True
            current = s[1:-1]
            if current == section:
                section_at = len(out)
            out.append(line)
            continue
        if current == section and "=" in s and s.split("=", 1)[0].strip() == key:
            if value is not None and not done:
                out.append(f"{key}={value}" if section else f"{key} = {value}")
                done = True
            continue
        out.append(line)
    if not done and value is not None:
        entry = f"{key}={value}" if section else f"{key} = {value}"
        if section is None:
            out.insert(0, entry)
        elif section_at is not None:
            out.append(entry)
        else:
            out += ([""] if out else []) + [f"[{section}]", entry]
    return write_if_changed(path, "\n".join(out) + "\n")


# ---- Firefox: our Pywalfox host ----

def mozilla_hosts():
    return HOME / ".mozilla" / "native-messaging-hosts"


def install_firefox(record):
    hosts = mozilla_hosts()
    manifest = hosts / "pywalfox.json"
    wrapper = DATA / "pywalfox-host"
    write_if_changed(wrapper, "#!/bin/sh\n# Rutile Shell's Pywalfox host (tools/apptheme.py wrote this)\n"
                              f"exec python3 '{ROOT / 'tools' / 'pywalfox_host.py'}' \"$@\"\n")
    os.chmod(wrapper, 0o755)
    ours = {"name": "pywalfox", "description": "Rutile Shell's colors for Firefox (Pywalfox)",
            "path": str(wrapper), "type": "stdio", "allowed_extensions": ["pywalfox@frewacom.org"]}
    text = json.dumps(ours, indent=2) + "\n"
    if manifest.exists() and manifest.read_text() != text and "backup" not in record:
        backup = hosts / "pywalfox.json.rutile-backup"
        shutil.copy2(manifest, backup)
        record["backup"] = str(backup)
    write_if_changed(manifest, text)
    record["manifest"] = str(manifest)
    record["wrapper"] = str(wrapper)


def remove_firefox(record):
    manifest = Path(record.get("manifest", mozilla_hosts() / "pywalfox.json"))
    if record.get("backup") and Path(record["backup"]).exists():
        os.replace(record["backup"], manifest)
    elif manifest.exists():
        manifest.unlink()
    wrapper = Path(record.get("wrapper", DATA / "pywalfox-host"))
    if wrapper.exists():
        wrapper.unlink()


# ---- sync ----

def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {"apps": {}}


def save_state(state):
    write_if_changed(STATE, json.dumps(state, indent=2) + "\n")


def render(palette, apps, matugen="matugen"):
    """{template name: text} for the apps, from matugen with the palette's source and settings."""
    names = sorted({t for a in apps for t, _ in APPS[a]["files"]})
    if not names:
        return {}
    doc = json.loads(Path(palette).read_text())
    with tempfile.TemporaryDirectory() as tmp:
        cfg = ["[config]", "version_check = false", "caching = false"]
        for n in names:
            cfg += [f"[templates.{n.replace('.', '-')}]", f'input_path = "{TEMPLATES / n}"',
                    f'output_path = "{tmp}/out/{n}"']
        conf = Path(tmp) / "matugen.toml"
        conf.write_text("\n".join(cfg) + "\n")
        cmd = [matugen, "-q", "-c", str(conf), "color", "hex", doc["source_color"],
               "-t", doc.get("scheme", "scheme-tonal-spot"), "-m", doc["mode"],
               "--contrast", str(doc.get("contrast", 0))]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise ThemeError(f"matugen failed (exit {proc.returncode}): {proc.stderr.strip()[-300:]}")
        return {n: (Path(tmp) / "out" / n).read_text() for n in names}


def reload(app):
    spec = APPS[app].get("reload")
    if not spec:
        return
    sig, pattern = spec
    subprocess.run(["pkill", f"-{sig}", "-f", pattern], capture_output=True)


def install(app, texts, record):
    spec = APPS[app]
    changed = False
    record.setdefault("files", [])
    for template, dest in spec["files"]:
        changed |= write_if_changed(dest, texts[template])
        if str(dest) not in record["files"]:
            record["files"].append(str(dest))
    for b in spec.get("blocks", []):
        changed |= add_block(b["file"], b["comment"], b["lines"], b["where"])
    previous = record.setdefault("previous", {})
    for path, section, key, value in spec.get("keys", []):
        slot = f"{path}|{section or ''}|{key}"
        if slot not in previous:
            previous[slot] = get_key(path, section, key)
        changed |= set_key(path, section, key, value)
    if spec.get("firefox"):
        install_firefox(record)
    return changed


def remove(app, record):
    spec = APPS.get(app, {})
    for f in record.get("files", []):
        if Path(f).exists():
            Path(f).unlink()
    for b in spec.get("blocks", []):
        remove_block(b["file"], b["comment"])
    for slot, old in record.get("previous", {}).items():
        path, section, key = slot.split("|")
        ours = next((v for p, s, k, v in spec.get("keys", []) if str(p) == path and (s or "") == section
                     and k == key), None)
        if get_key(path, section or None, key) == ours:          # still ours: put theirs back
            set_key(path, section or None, key, old)
    if spec.get("firefox"):
        remove_firefox(record)


def sync(palette, apps, matugen="matugen"):
    unknown = [a for a in apps if a not in APPS]
    if unknown:
        raise ThemeError(f"unknown apps: {', '.join(unknown)} (known: {', '.join(APPS)})")
    state = load_state()
    done = state.setdefault("apps", {})
    for app in [a for a in list(done) if a not in apps]:
        remove(app, done.pop(app))
        reload(app)
    texts = render(palette, apps, matugen) if apps else {}
    for app in apps:
        record = done.setdefault(app, {})
        if install(app, texts, record):
            reload(app)
    save_state(state)
    return sorted(done)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sync")
    s.add_argument("--palette", required=True)
    s.add_argument("--apps", default="", help="comma-separated; empty: none")
    s.add_argument("--matugen", default="matugen")
    sub.add_parser("apps")
    a = p.parse_args(argv)
    if a.cmd == "apps":
        for k, v in APPS.items():
            print(f"{k}\t{v['title']}")
        return 0
    try:
        themed = sync(a.palette, [x for x in a.apps.split(",") if x], a.matugen)
    except (ThemeError, OSError, ValueError, KeyError) as e:
        print(f"apptheme error: {e}", file=sys.stderr)
        return 2
    print("themed: " + (", ".join(themed) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
