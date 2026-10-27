"""The `rutile-shell` command (bin/rutile-shell, plan 6.1): its help lists exactly the IPC targets and functions that
shell/shell.qml's IpcHandlers answer, with their arguments, and each form of the command reaches Quickshell with
the right arguments (a stand-in quickshell prints what it got)."""
import os
import re
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


if __name__ == "__main__":
    unittest.main()
