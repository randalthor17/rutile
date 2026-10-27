"""Drift guards for the handoff documents: they must keep describing the repository that exists."""
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC_PATHS = ["docs/HANDOFF.md", "docs/PLAN.md", "docs/DECISIONS.md", "docs/LESSONS.md", "CHANGELOG.md",
             "AGENTS.md", "README.md", "docs/editable-grid.md"]
# Paths the docs mention that do not exist (yet) on purpose: planned work, user-generated or output directories.
PLANNED = {
    "docs/reference", "widgets/spec.schema.json", "docs/llm/TOKENS.md", "docs/llm/COMPONENTS.md",
    "docs/sidework/tasks", "render", "render-modern", "build/rutile-pywalfox-host",  # build outputs
}


def read(rel):
    return (ROOT / rel).read_text()


def backticked(text):
    return re.findall(r"`([^`\n]+)`", text)


class RequiredDocs(unittest.TestCase):
    def test_every_handoff_document_exists_and_is_not_trivial(self):
        for rel in DOC_PATHS:
            self.assertGreater(len(read(rel)), 400, rel)

    def test_readme_and_agents_point_at_the_handoff(self):
        self.assertIn("docs/HANDOFF.md", read("README.md"))
        agents = read("AGENTS.md")
        for needle in ("docs/HANDOFF.md", "docs/PLAN.md", "docs/sidework/CONVENTIONS.md", "make check"):
            self.assertIn(needle, agents, needle)

    def test_handoff_states_the_source_of_truth_and_memory_rule(self):
        text = " ".join(read("docs/HANDOFF.md").split())
        self.assertIn("The repository is the source of truth", text)
        self.assertIn("memory", text)
        self.assertIn("docs/PLAN.md", text)

    def test_handoff_has_a_resume_prompt_and_the_release_protocol(self):
        text = read("docs/HANDOFF.md")
        for needle in ("## 8. Resume prompt", "Read `docs/HANDOFF.md`", "### Release protocol", "git bundle verify"):
            self.assertIn(needle, text, needle)


class PlanFormat(unittest.TestCase):
    LINE = re.compile(r"^- \[( |x)\] \*\*([A-Za-z0-9.]+)\*\* ")

    @classmethod
    def setUpClass(cls):
        cls.lines = [l for l in read("docs/PLAN.md").splitlines() if l.startswith("- [")]
        cls.items = {}
        for l in cls.lines:
            m = cls.LINE.match(l)
            if m:
                cls.items.setdefault(m.group(2), []).append(m.group(1))

    def test_every_checklist_line_is_well_formed(self):
        for l in self.lines:
            self.assertRegex(l, self.LINE, l[:70])

    def test_ids_are_unique(self):
        dups = [k for k, v in self.items.items() if len(v) > 1]
        self.assertEqual(dups, [])

    def test_expected_ids_exist(self):
        want = ["0.1", "0.2", "0.3", "0.4", "1.1", "1.1b", "1.2", "1.3", "1.3b", "1.4", "1.5a", "1.5b", "1.5c", "1.5d", "1.5", "1.6",
                "1.7", "2.1", "2.8", "3.1", "4.1", "4.10", "5.1", "5.2", "6.1", "6.3", "7.1", "L1", "L2", "L3",
                "S1", "S2", "S3", "H1", "H2", "H3"]
        for i in want:
            self.assertIn(i, self.items, f"plan item {i} is missing")

    def test_finished_work_is_ticked_and_open_work_is_not(self):
        done = ["0.1", "0.3", "0.4", "1.1", "1.2", "1.3", "1.3b", "1.4", "1.5a", "1.5b", "1.5c", "1.5d", "1.6", "4.1", "S1", "H1"]
        todo = ["1.5", "2.1", "4.2", "5.1", "6.1", "S2", "S3", "H3"]
        for i in done:
            self.assertEqual(self.items[i], ["x"], f"{i} should be done")
        for i in todo:
            self.assertEqual(self.items[i], [" "], f"{i} should be open")

    def test_plan_item_references_in_other_docs_exist(self):
        for rel in ("docs/HANDOFF.md", "docs/DECISIONS.md", "docs/LESSONS.md", "CHANGELOG.md"):
            for ref in re.findall(r"plan items? (\d+\.\d+[a-z]?)", read(rel)):
                self.assertIn(ref, self.items, f"{rel} refers to plan item {ref}")


class Decisions(unittest.TestCase):
    def test_numbering_is_contiguous_and_references_resolve(self):
        text = read("docs/DECISIONS.md")
        ids = [int(n) for n in re.findall(r"^\*\*D(\d+)\.", text, re.M)]
        self.assertEqual(ids, list(range(1, len(ids) + 1)))
        for rel in DOC_PATHS:
            for n in re.findall(r"\bD(\d+)\b", read(rel)):
                if rel != "docs/DECISIONS.md":
                    self.assertLessEqual(int(n), len(ids), f"{rel} cites D{n}")


def tracked_paths():
    """Paths git knows about (files plus every directory containing one), or None outside a git checkout.

    Looking at the filesystem would let untracked leftovers (empty directories, ignored output) hide a doc that
    mentions something a fresh clone does not have, which is exactly how a bundle once shipped a failing check.
    """
    r = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    files = set(r.stdout.splitlines())
    dirs = {str(Path(f).parent.as_posix()) for f in files}
    for d in list(dirs):
        parts = Path(d).parts
        dirs |= {"/".join(parts[:i]) for i in range(1, len(parts) + 1)}
    return files | dirs


class DocsMatchTheRepository(unittest.TestCase):
    @staticmethod
    def candidates(text):
        for tok in backticked(text):
            if not re.fullmatch(r"[A-Za-z0-9_./-]+", tok) or "/" not in tok:
                continue
            if tok.startswith(("http", "/", "../", "./", "~")) or tok.startswith(("local/", "refs/")):
                continue
            yield tok

    def test_every_path_mentioned_in_the_docs_exists_or_is_deliberately_planned(self):
        missing = []
        tracked = tracked_paths()
        for rel in DOC_PATHS:
            for tok in self.candidates(read(rel)):
                path = tok.rstrip("/")
                exists = (path in tracked) if tracked is not None else (ROOT / path).exists()
                if path in PLANNED or exists:
                    continue
                missing.append(f"{rel}: {tok}")
        self.assertEqual(missing, [], "docs mention paths that do not exist; fix the docs or add to PLANNED")

    def test_every_tool_script_is_in_the_handoff_inventory(self):
        text = read("docs/HANDOFF.md")
        tools = [p for p in (ROOT / "tools").glob("*.py")] + list((ROOT / "tools" / "dev").glob("*"))
        for p in tools:
            if p.name == "__pycache__" or p.is_dir():
                continue
            self.assertTrue(f"tools/{p.name}" in text or f"tools/dev/{p.name}" in text or f"`{p.name}`" in text,
                            f"{p.name} is not mentioned in docs/HANDOFF.md")

    def test_every_environment_variable_is_documented(self):
        text = read("docs/HANDOFF.md")
        used = set()
        for sub in ("tools", "tests", "shell"):
            for p in (ROOT / sub).rglob("*"):
                if p.is_file() and p.suffix in (".py", ".qml", ".sh", ".js"):
                    used |= set(re.findall(r"RUTILE_[A-Z_]+", p.read_text()))
        used |= set(re.findall(r"RUTILE_[A-Z_]+", read("flake.nix")))
        for var in sorted(used):
            self.assertIn(var, text, f"{var} is used by the code but not documented in docs/HANDOFF.md")

    def test_every_git_tag_has_a_changelog_section(self):
        tags = subprocess.run(["git", "tag", "--list", "v*"], cwd=ROOT, capture_output=True, text=True)
        if tags.returncode != 0 or not tags.stdout.split():
            self.skipTest("not a git checkout with tags; SKIPPED")
        text = read("CHANGELOG.md")
        for tag in tags.stdout.split():
            self.assertIn(f"## {tag[1:]}", text, f"{tag} has no CHANGELOG section")

    def test_changelog_has_an_unreleased_section(self):
        self.assertIn("## Unreleased", read("CHANGELOG.md"))


class BehaviorDocsCiteRealTests(unittest.TestCase):
    """A behavior doc names the test that pins each rule; a renamed or deleted test must not leave it pointing
    at nothing (docs/editable-grid.md)."""

    def test_cited_qml_tests_exist(self):
        defined = set()
        for f in (ROOT / "tests" / "qml").glob("tst_*.qml"):
            defined |= set(re.findall(r"function (test_\w+)\s*\(", f.read_text()))
        cited = set(re.findall(r"`(test_\w+)`", read("docs/editable-grid.md")))
        self.assertTrue(cited, "the grid doc cites its tests")
        self.assertEqual(sorted(cited - defined), [], "docs/editable-grid.md cites tests that do not exist")


class TrackedPathLogic(unittest.TestCase):
    def test_tracked_paths_include_files_and_their_directories_but_not_untracked_things(self):
        tracked = tracked_paths()
        self.assertIsNotNone(tracked, "these tests are meant to run in a git checkout")
        for p in ("docs/HANDOFF.md", "docs", "tools/dev", "tools/dev/setup_sandbox.sh", "widgets/README.md", "widgets"):
            self.assertIn(p, tracked, p)
        for p in ("docs/definitely-not-here.md", "render"):
            self.assertNotIn(p, tracked, p)

    def test_reserved_directories_are_real_tracked_content(self):
        tracked = tracked_paths()
        for d in ("widgets", "settings"):
            self.assertIn(d, tracked, f"{d}/ must contain a tracked file or it will not exist in a clone")


class DevTools(unittest.TestCase):
    TOOLS = ("pyside_qml.py", "eval_flake.sh", "setup_sandbox.sh")

    def test_scripts_exist_are_executable_and_parse(self):
        for name in self.TOOLS:
            p = ROOT / "tools" / "dev" / name
            self.assertTrue(p.exists(), name)
            self.assertTrue(os.access(p, os.X_OK), f"{name} is not executable")
        for name in ("eval_flake.sh", "setup_sandbox.sh"):
            r = subprocess.run(["sh", "-n", str(ROOT / "tools" / "dev" / name)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
        r = subprocess.run([sys.executable, "-m", "py_compile", str(ROOT / "tools" / "dev" / "pyside_qml.py")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_setup_script_prints_the_environment_the_tests_read(self):
        text = read("tools/dev/setup_sandbox.sh")
        for var in ("RUTILE_MATUGEN", "RUTILE_FONT_DIRS", "RUTILE_OPENCODE"):
            self.assertIn(var, text, var)
        self.assertNotRegex(text, r"mkdir -p [^\n]*\{[^}\n]*,[^}\n]*\}", "sh has no brace expansion")

    def test_eval_script_avoids_the_github_api(self):
        text = read("tools/dev/eval_flake.sh")
        self.assertIn("codeload.github.com", text)
        self.assertIn("--override-input", text)
        self.assertIn("--no-write-lock-file", text)

    def test_pyside_runner_help_and_missing_dependency_message(self):
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "dev" / "pyside_qml.py"), "--help"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        for word in ("suite", "file", "render", "--gl", "xvfb-run"):
            self.assertIn(word, r.stdout, word)

    def test_pyside_runner_runs_a_real_test_file_on_a_modern_qt(self):
        try:
            import PySide6.QtQuickTest  # noqa: F401
        except ImportError:
            self.skipTest("PySide6 not installed (pip install PySide6-Essentials PySide6-Addons); SKIPPED")
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "dev" / "pyside_qml.py"), "suite", "--only", "tst_spring"],
                           capture_output=True, text=True, timeout=300)
        self.assertEqual(r.returncode, 0, (r.stdout + r.stderr)[-1500:])
        self.assertRegex(r.stdout, r"Totals: \d+ passed, 0 failed")
        self.assertIn("Qt 6.", r.stdout)


if __name__ == "__main__":
    unittest.main()
