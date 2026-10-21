import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import sidework as sw  # noqa: E402

GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")


def run(args, cwd, env=None, check=True):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=env or GIT_ENV)
    if check and p.returncode != 0:
        raise AssertionError(f"{args} failed: {p.stderr}{p.stdout}")
    return p


def make_repo(tmp):
    """A repo shaped like the real one, with the real sidework files copied in."""
    repo = Path(tmp) / "repo"
    (repo / "tools" / "hooks").mkdir(parents=True)
    for f in ("sidework.py", "ownership.json", "local_models.json"):
        shutil.copy(ROOT / "tools" / f, repo / "tools" / f)
    shutil.copy(ROOT / "tools" / "hooks" / "pre-commit", repo / "tools" / "hooks" / "pre-commit")
    os.chmod(repo / "tools" / "hooks" / "pre-commit", 0o755)
    for rel, text in {"README.md": "readme\n", "docs/guide.md": "guide\n", "shell/a.qml": "// a\n",
                      "widgets/spec.json": "{}\n", "docs/llm/notes.md": "notes\n", "Makefile": "check:\n\ttrue\n"}.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    run(["git", "init", "-q", "-b", "main"], repo)
    run(["git", "add", "-A"], repo)
    run(["git", "commit", "-q", "-m", "init"], repo)
    return repo


def tool(repo, *args, cwd=None):
    return run([sys.executable, str(repo / "tools" / "sidework.py"), *args], cwd or repo, check=False)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = make_repo(self.tmp)

    def start(self, task="demo", *extra):
        wt = Path(self.tmp) / f"wt-{task}"
        p = tool(self.repo, "start", task, "--dir", str(wt), *extra)
        self.assertEqual(p.returncode, 0, p.stderr)
        return wt

    def commit(self, wt, files, msg="work", verify=True):
        for rel, text in files.items():
            f = wt / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(text)
        run(["git", "add", "-A"], wt)
        return run(["git", "commit", "-q", "-m", msg] + ([] if verify else ["--no-verify"]), wt, check=False)


class GlobMatching(unittest.TestCase):
    def test_patterns(self):
        cases = [("widgets/**", "widgets/a/b.json", True), ("widgets/**", "widgets", False),
                 ("widgets/**", "xwidgets/a", False), ("docs/*.md", "docs/a.md", True),
                 ("docs/*.md", "docs/sub/a.md", False), ("**/*.md", "a.md", True), ("**/*.md", "x/y/a.md", True),
                 ("tools/hooks/**", "tools/hooks/pre-commit", True), ("a?c", "abc", True), ("a?c", "a/c", False),
                 ("README.md", "README.md", True), ("README.md", "docs/README.md", False)]
        for pat, path, want in cases:
            self.assertEqual(sw.matches(path, [pat]), want, f"{pat} vs {path}")

    def test_pattern_chars_are_escaped(self):
        self.assertTrue(sw.matches("a.b", ["a.b"]))
        self.assertFalse(sw.matches("axb", ["a.b"]))
        self.assertTrue(sw.matches("x[1].json", ["x[1].json"]))

    def test_parse_name_status_includes_both_sides_of_renames(self):
        raw = "M\0a.txt\0R100\0old.txt\0new.txt\0D\0gone.txt\0"
        self.assertEqual(sw.parse_name_status_z(raw), ["a.txt", "old.txt", "new.txt", "gone.txt"])


class RealConfig(unittest.TestCase):
    def test_ownership_is_consistent(self):
        cfg = sw.load_config()
        self.assertTrue(cfg["local_owned"])
        for pat in cfg["local_owned"]:
            for forbidden in cfg["always_forbidden"]:
                probe = pat.replace("**", "x").replace("*", "x")
                self.assertFalse(sw.matches(probe, [forbidden]), f"{pat} overlaps forbidden {forbidden}")
        for must in ("tools/sidework.py", "tools/ownership.json", "tools/hooks/**", "flake.nix", ".git/**"):
            self.assertIn(must, cfg["always_forbidden"])

    def test_nothing_claude_owns_is_local_owned(self):
        cfg = sw.load_config()
        for claude_path in ("shell/common/Colors.qml", "tools/gen_qml.py", "tokens/m3e.json", "tests/test_qml.py",
                            "theme/fonts.json", "nix/googlesans-flex.nix"):
            self.assertFalse(sw.matches(claude_path, cfg["local_owned"]), claude_path)

    def test_hook_is_executable_and_calls_guard(self):
        hook = ROOT / "tools" / "hooks" / "pre-commit"
        self.assertTrue(os.access(hook, os.X_OK))
        self.assertIn("sidework.py", hook.read_text())
        self.assertIn("guard", hook.read_text())

    def test_model_tiers_are_sane(self):
        m = sw.load_models()
        self.assertIn(m["default_tier"], m["tiers"])
        for name, t in m["tiers"].items():
            self.assertTrue(t["tag"] and t["approx_gb"] > 0 and t["note"], name)
        ok, _ = sw.fits(m["tiers"][m["default_tier"]], m)
        self.assertTrue(ok, "the default tier must fit the GPU")
        ok, need = sw.fits(m["tiers"]["stretch"], m)
        self.assertFalse(ok, "the stretch tier is documented as spilling to the CPU")
        self.assertEqual(m["env"]["OLLAMA_KV_CACHE_TYPE"], "q8_0")


class Consistency(unittest.TestCase):
    """Docs, config, task briefs, flake and NixOS module must agree with each other."""

    TASKS = ("widget-schema", "llm-docs", "widget-templates")

    def brief(self, task):
        return (ROOT / "docs" / "sidework" / "tasks" / f"{task}.md").read_text()

    def test_every_brief_has_its_sections_and_only_names_owned_paths(self):
        import re
        cfg = sw.load_config()
        for task in self.TASKS:
            text = self.brief(task)
            for section in ("## Goal", "## Files you may touch", "## Acceptance", "## Out of scope"):
                self.assertIn(section, text, f"{task}: missing {section}")
            sec = re.search(r"## Files you may touch\n(.*?)\n## ", text, re.S).group(1)
            paths = re.findall(r"`([^`]+)`", sec)
            self.assertTrue(paths, task)
            for path in paths:
                self.assertTrue(sw.matches(path, cfg["local_owned"]), f"{task}: {path} is not local-owned")
                self.assertFalse(sw.matches(path, cfg["always_forbidden"]), f"{task}: {path} is forbidden")

    def test_task_names_are_valid_branch_slugs(self):
        for task in self.TASKS:
            self.assertRegex(task, sw.TASK_RE.pattern)

    def test_conventions_state_the_hard_rules(self):
        text = (ROOT / "docs" / "sidework" / "CONVENTIONS.md").read_text()
        for needle in ("rejected by a hook", "tools/", "flake.nix", "primaryOn", "Do not invent facts"):
            self.assertIn(needle, text, needle)

    def test_the_plan_documents_every_command(self):
        doc = (ROOT / "docs" / "sidework.md").read_text()
        for cmd in ("start", "agent", "check", "merge-check", "bundle", "status", "models", "serve"):
            self.assertIn(f"sidework.py {cmd}", doc, cmd)
            self.assertIn(f"sidework.py {cmd}", sw.__doc__, cmd)

    def test_the_documented_default_model_is_the_configured_one(self):
        m = sw.load_models()
        doc = (ROOT / "docs" / "sidework.md").read_text()
        self.assertIn(m["tiers"][m["default_tier"]]["tag"], doc)
        for tier in m["tiers"].values():
            self.assertIn(tier["tag"], doc, tier["tag"])

    def test_nixos_module_environment_matches_the_models_config(self):
        import re
        text = (ROOT / "nix" / "local-ai-module.nix").read_text()
        in_module = dict(re.findall(r'(OLLAMA_[A-Z_]+)\s*=\s*"([^"]*)";', text))
        wanted = sw.load_models()["env"]
        self.assertEqual(in_module, wanted)

    def test_docs_describe_the_opencode_workflow_and_its_limits_honestly(self):
        doc = " ".join((ROOT / "docs" / "sidework.md").read_text().split())   # independent of line wrapping
        for needle in ("opencode", "sidework.py prepare", "OPENCODE_CONFIG_CONTENT", "tool_call", "not a sandbox"):
            self.assertIn(needle, doc, needle)
        self.assertNotIn("aider", doc.lower(), "aider was dropped; the docs must not send people to it")
        self.assertIn("always forbidden", doc.lower().replace("*", ""))

    def test_nothing_in_the_repo_still_points_at_aider(self):
        for rel in ("tools/sidework.py", "flake.nix", "docs/sidework/CONVENTIONS.md", "README.md"):
            self.assertNotIn("aider", (ROOT / rel).read_text().lower(), rel)

    def test_context_is_consistent_between_agent_config_server_env_and_module(self):
        m = sw.load_models()
        self.assertEqual(int(m["env"]["OLLAMA_CONTEXT_LENGTH"]), m["context"])
        self.assertGreaterEqual(m["context"], 32768, "an agent's system prompt and tools need a long context")

    def test_tiers_are_tool_capable_families_not_the_one_reported_to_hang(self):
        m = sw.load_models()
        for name, t in m["tiers"].items():
            self.assertNotIn("qwen2.5-coder", t["tag"], name)
            self.assertIn("temperature", t, name)


class StartAndGuard(Base):
    def test_start_creates_branch_worktree_hook_and_allowlist(self):
        wt = self.start()
        self.assertTrue((wt / "tools" / "sidework.py").exists())
        self.assertEqual(run(["git", "symbolic-ref", "--short", "HEAD"], wt).stdout.strip(), "local/demo")
        self.assertEqual(run(["git", "config", "core.hooksPath"], self.repo).stdout.strip(),
                         str(self.repo / "tools" / "hooks"), "must be absolute, in the main checkout")
        state = json.loads((self.repo / ".git" / "rutile-sidework" / "local__demo.json").read_text())
        self.assertEqual(state["paths"], sw.load_config()["local_owned"])

    def test_start_rejects_bad_names_and_duplicates(self):
        for bad in ("Bad Name", "x/y", "-lead", "a" * 60, ""):
            self.assertNotEqual(tool(self.repo, "start", bad, "--dir", str(Path(self.tmp) / "w")).returncode, 0, bad)
        self.start("dup")
        again = tool(self.repo, "start", "dup", "--dir", str(Path(self.tmp) / "w2"))
        self.assertEqual(again.returncode, 2)
        self.assertIn("already exists", again.stderr)

    def test_owned_paths_commit_fine(self):
        wt = self.start()
        p = self.commit(wt, {"widgets/new.json": "{}\n", "docs/llm/guide.md": "x\n"})
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_commit_outside_the_allowlist_is_rejected_by_the_hook(self):
        wt = self.start()
        p = self.commit(wt, {"widgets/ok.json": "{}\n", "shell/a.qml": "// changed\n"})
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("shell/a.qml", p.stderr)
        self.assertIn("outside the allowed paths", p.stderr)
        self.assertEqual(run(["git", "rev-list", "--count", "main..HEAD"], wt).stdout.strip(), "0")

    def test_deleting_or_renaming_a_foreign_file_is_rejected(self):
        wt = self.start()
        (wt / "docs" / "guide.md").unlink()
        run(["git", "add", "-A"], wt)
        self.assertNotEqual(run(["git", "commit", "-q", "-m", "rm"], wt, check=False).returncode, 0)
        run(["git", "reset", "-q", "--hard"], wt)
        run(["git", "mv", "shell/a.qml", "widgets/a.qml"], wt)
        p = run(["git", "commit", "-q", "-m", "mv"], wt, check=False)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("shell/a.qml", p.stderr)

    def test_always_forbidden_wins_even_if_the_allowlist_says_otherwise(self):
        wt = self.start("greedy", "--path", "tools/**", "--path", "widgets/**")
        edits = {"tools/sidework.py": lambda t: t + "\n# tamper\n",
                 "tools/ownership.json": lambda t: json.dumps({**json.loads(t), "extra": 1}, indent=2) + "\n",
                 "tools/hooks/pre-commit": lambda t: t + "\n# tamper\n"}
        for rel, edit in edits.items():
            run(["git", "reset", "-q", "--hard"], wt)
            p = self.commit(wt, {rel: edit((wt / rel).read_text())})
            self.assertNotEqual(p.returncode, 0, rel)
            self.assertIn("always forbidden", p.stderr, rel)
        run(["git", "reset", "-q", "--hard"], wt)
        self.assertEqual(self.commit(wt, {"tools/extra.py": "x\n"}).returncode, 0)

    def test_attack_weakening_the_rules_in_the_worktree_does_not_work(self):
        """A task granted tools/** empties always_forbidden in the worktree copy of ownership.json (uncommitted),
        then commits a change to the guard itself. Only the main checkout's rules may count."""
        wt = self.start("attack1", "--path", "tools/**")
        cfg = json.loads((wt / "tools" / "ownership.json").read_text())
        cfg["always_forbidden"] = []
        (wt / "tools" / "ownership.json").write_text(json.dumps(cfg, indent=2) + "\n")
        (wt / "tools" / "sidework.py").write_text((wt / "tools" / "sidework.py").read_text() + "\n# backdoor\n")
        run(["git", "add", "tools/sidework.py"], wt)
        p = run(["git", "commit", "-q", "-m", "sneak"], wt, check=False)
        self.assertNotEqual(p.returncode, 0, "the worktree's copy of the rules must not be trusted")
        self.assertIn("always forbidden", p.stderr)

    def test_attack_disabling_the_guard_code_in_the_worktree_does_not_work(self):
        """Replace tools/sidework.py in the worktree with a guard that always allows, then commit a foreign file."""
        wt = self.start("attack2")
        (wt / "tools" / "sidework.py").write_text("import sys\nsys.exit(0)\n")
        (wt / "tools" / "hooks" / "pre-commit").write_text("#!/bin/sh\nexit 0\n")
        (wt / "shell" / "a.qml").write_text("// foreign edit\n")
        run(["git", "add", "shell/a.qml"], wt)
        p = run(["git", "commit", "-q", "-m", "sneak"], wt, check=False)
        self.assertNotEqual(p.returncode, 0, "the hook must run the main checkout's guard")
        self.assertIn("shell/a.qml", p.stderr)

    def test_the_state_file_with_the_allowlist_lives_outside_the_worktree(self):
        wt = self.start("outside")
        self.assertFalse(any("rutile-sidework" in str(p) for p in wt.rglob("*") if ".git" not in p.parts))
        self.assertTrue((self.repo / ".git" / "rutile-sidework" / "local__outside.json").exists())

    def test_per_task_allowlist_narrows_the_area(self):
        wt = self.start("narrow", "--path", "widgets/templates/**")
        self.assertEqual(self.commit(wt, {"widgets/templates/a.json": "{}\n"}).returncode, 0)
        p = self.commit(wt, {"widgets/spec.json": '{"x": 1}\n'})
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("widgets/spec.json", p.stderr)

    def test_the_hook_does_nothing_on_main(self):
        (self.repo / "shell" / "a.qml").write_text("// edited on main\n")
        run(["git", "add", "-A"], self.repo)
        self.assertEqual(run(["git", "commit", "-q", "-m", "main edit"], self.repo, check=False).returncode, 0)


class CheckMergeBundle(Base):
    def test_check_passes_for_a_compliant_branch_and_fails_when_the_hook_was_bypassed(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n"}).returncode, 0)
        ok = tool(self.repo, "check", "demo")
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn("widgets/a.json", ok.stdout)
        self.assertEqual(self.commit(wt, {"README.md": "sneaky\n"}, verify=False).returncode, 0)
        bad = tool(self.repo, "check", "demo")
        self.assertEqual(bad.returncode, 1)
        self.assertIn("README.md", bad.stderr)

    def test_check_with_make_check_runs_in_the_worktree(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n"}).returncode, 0)
        self.assertEqual(tool(self.repo, "check", "demo", "--run-checks").returncode, 0)
        (wt / "Makefile").write_text("check:\n\tfalse\n")
        run(["git", "add", "-A"], wt)
        run(["git", "commit", "-q", "-m", "break", "--no-verify"], wt)
        res = tool(self.repo, "check", "demo", "--run-checks")
        self.assertEqual(res.returncode, 1)

    def test_disjoint_work_merges_cleanly_even_after_main_moves(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n"}).returncode, 0)
        (self.repo / "shell" / "a.qml").write_text("// main moved on\n")
        run(["git", "add", "-A"], self.repo)
        run(["git", "commit", "-q", "-m", "main work"], self.repo)
        ok = tool(self.repo, "merge-check", "demo")
        self.assertEqual(ok.returncode, 0, ok.stderr)
        run(["git", "merge", "-q", "--no-edit", "local/demo"], self.repo)
        self.assertTrue((self.repo / "widgets" / "a.json").exists())
        self.assertEqual((self.repo / "shell" / "a.qml").read_text(), "// main moved on\n")

    def test_overlapping_edits_are_reported_as_conflicts(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/spec.json": '{"local": 1}\n'}).returncode, 0)
        (self.repo / "widgets" / "spec.json").write_text('{"main": 1}\n')
        run(["git", "add", "-A"], self.repo)
        run(["git", "commit", "-q", "-m", "main touches a local-owned file"], self.repo)
        res = tool(self.repo, "merge-check", "demo")
        self.assertEqual(res.returncode, 1)
        self.assertIn("widgets/spec.json", res.stderr)
        self.assertEqual(run(["git", "status", "--porcelain"], self.repo).stdout.strip(), "", "dry run must not touch the tree")

    def test_bundle_is_verifiable_and_importable(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n", "docs/llm/x.md": "x\n"}, "local work").returncode, 0)
        out = Path(self.tmp) / "demo.bundle"
        res = tool(self.repo, "bundle", "demo", "--out", str(out))
        self.assertEqual(res.returncode, 0, res.stderr)
        other = Path(self.tmp) / "other"
        run(["git", "clone", "-q", str(self.repo), str(other)], self.tmp)
        run(["git", "fetch", "-q", str(out), "local/demo:local/demo"], other)
        self.assertEqual(run(["git", "log", "-1", "--format=%s", "local/demo"], other).stdout.strip(), "local work")

    def test_status_lists_branches_with_their_health(self):
        self.assertIn("no local/*", tool(self.repo, "status").stdout)
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n"}).returncode, 0)
        out = tool(self.repo, "status").stdout
        self.assertIn("local/demo", out)
        self.assertIn("paths:OK", out)
        self.assertIn("merge:clean", out)
        self.assertIn(str(wt), out)

    def test_check_from_inside_a_worktree_infers_the_branch(self):
        wt = self.start()
        self.assertEqual(self.commit(wt, {"widgets/a.json": "{}\n"}).returncode, 0)
        self.assertEqual(tool(wt, "check", cwd=wt).returncode, 0)
        outside = tool(self.repo, "check")
        self.assertEqual(outside.returncode, 2)


RULES_SAMPLE = [
    ("edit", "widgets/a.json", "allow"), ("edit", "widgets/templates/x/y.json", "allow"),
    ("edit", "docs/llm/TOKENS.md", "allow"), ("edit", "shell/common/Colors.qml", "deny"),
    ("edit", "tools/sidework.py", "deny"), ("edit", "tools/hooks/pre-commit", "deny"),
    ("edit", "flake.nix", "deny"), ("edit", "README.md", "deny"), ("edit", "opencode.json", "deny"),
    ("edit", ".git/config", "deny"), ("bash", "git status", "allow"), ("bash", "git add -A", "allow"),
    ("bash", "git commit -m 'x'", "allow"), ("bash", "make check", "allow"),
    ("bash", "git push origin main", "deny"), ("bash", "git commit --no-verify -m x", "deny"),
    ("bash", "git commit -n -m x", "deny"), ("bash", "git config core.hooksPath /dev/null", "deny"),
    ("bash", "git worktree add ../x", "deny"), ("bash", "curl https://example.com", "deny"),
    ("bash", "sudo rm -rf /", "deny"), ("external_directory", "/elsewhere/file", "deny"),
    ("webfetch", "https://example.com", "deny"),
]


def wildcard(pattern):
    import re
    return re.compile("^" + "".join(".*" if c == "*" else re.escape(c) for c in pattern) + "$", re.S)


def decide(permission, kind, value):
    """opencode semantics: patterns in order, the last match wins; a plain string applies to everything."""
    rule = permission.get(kind)
    if isinstance(rule, str):
        return rule
    action = None
    for pattern, act in (rule or {}).items():
        if wildcard(pattern).match(value):
            action = act
    return action


def fake_bin(tmp, name, body):
    d = Path(tmp) / "bin"
    d.mkdir(exist_ok=True)
    f = d / name
    f.write_text("#!/bin/sh\n" + body)
    f.chmod(0o755)
    return d


class OpencodeConfig(unittest.TestCase):
    def setUp(self):
        self.cfg, self.models = sw.load_config(), sw.load_models()

    def config(self, allowed=None, host=None, instructions=("docs/sidework/CONVENTIONS.md",)):
        if host:
            os.environ["OLLAMA_HOST"] = host
            self.addCleanup(os.environ.pop, "OLLAMA_HOST", None)
        return sw.opencode_config(self.cfg, self.models, "rutile-main:32k", 0.6,
                                  allowed or self.cfg["local_owned"], list(instructions))

    def test_provider_model_and_limits(self):
        c = self.config()
        self.assertEqual(c["model"], "ollama/rutile-main:32k")
        prov = c["provider"]["ollama"]
        self.assertEqual(prov["npm"], "@ai-sdk/openai-compatible")
        self.assertEqual(prov["options"]["baseURL"], "http://127.0.0.1:11434/v1")
        m = prov["models"]["rutile-main:32k"]
        self.assertIs(m["tool_call"], True, "without tool_call opencode silently sends no tools")
        self.assertEqual(m["limit"], {"context": 32768, "output": 8192})
        self.assertEqual(m["options"]["temperature"], 0.6)

    def test_base_url_follows_the_host_and_accepts_a_scheme(self):
        self.assertEqual(self.config(host="10.0.0.5:11434")["provider"]["ollama"]["options"]["baseURL"], "http://10.0.0.5:11434/v1")
        self.assertEqual(self.config(host="https://gpu.lan")["provider"]["ollama"]["options"]["baseURL"], "https://gpu.lan/v1")

    def test_never_leaves_the_machine(self):
        c = self.config()
        self.assertEqual(c["enabled_providers"], ["ollama"])
        self.assertEqual(c["share"], "disabled")
        self.assertIs(c["autoupdate"], False)
        self.assertEqual(c["permission"]["webfetch"], "deny")
        self.assertEqual(c["permission"]["websearch"], "deny")

    def test_permission_decisions(self):
        perm = self.config()["permission"]
        for kind, value, want in RULES_SAMPLE:
            self.assertEqual(decide(perm, kind, value), want, f"{kind} {value}")

    def test_forbidden_paths_stay_denied_even_when_the_task_is_granted_a_wide_area(self):
        perm = self.config(allowed=["tools/**", "widgets/**"])["permission"]
        for path in ("tools/sidework.py", "tools/ownership.json", "tools/hooks/pre-commit", "flake.nix", "Makefile"):
            self.assertEqual(decide(perm, "edit", path), "deny", path)
        self.assertEqual(decide(perm, "edit", "tools/extra.py"), "allow")

    def test_per_task_allowlist_narrows_edits(self):
        perm = self.config(allowed=["widgets/templates/**"])["permission"]
        self.assertEqual(decide(perm, "edit", "widgets/templates/a.json"), "allow")
        self.assertEqual(decide(perm, "edit", "widgets/spec.schema.json"), "deny")

    def test_glob_translation(self):
        self.assertEqual(sw.glob_for_opencode("widgets/**"), "widgets/*")
        self.assertEqual(sw.glob_for_opencode("**/*.md"), "*.md")
        self.assertEqual(sw.glob_for_opencode("tools/hooks/**"), "tools/hooks/*")
        self.assertEqual(sw.glob_for_opencode("README.md"), "README.md")

    def test_bash_denies_cover_hook_skipping_and_leaving_the_repo(self):
        joined = " ".join(sw.BASH_DENY)
        for needle in ("git push", "git config", "git worktree", "--no-verify", "curl", "sudo"):
            self.assertIn(needle, joined, needle)

    def test_instructions_and_context_handling(self):
        c = self.config(instructions=("docs/sidework/CONVENTIONS.md", "docs/sidework/tasks/t.md"))
        self.assertEqual(c["instructions"], ["docs/sidework/CONVENTIONS.md", "docs/sidework/tasks/t.md"])
        self.assertTrue(c["compaction"]["auto"])
        self.assertIs(c["snapshot"], False)

    def test_config_is_json_serializable_and_stable(self):
        c = self.config()
        self.assertEqual(json.loads(json.dumps(c)), c)
        self.assertEqual(list(c["permission"]["edit"])[0], "*", "the catch-all must come first (last match wins)")
        self.assertEqual(list(c["permission"]["bash"])[0], "*")

    def test_derived_model_and_modelfile(self):
        self.assertEqual(sw.derived_name("main", self.models), "rutile-main:32k")
        text = sw.modelfile_text("qwen3:14b", self.models, 0.6)
        self.assertEqual(text.splitlines(), ["FROM qwen3:14b", "PARAMETER num_ctx 32768", "PARAMETER temperature 0.6"])

    def test_default_prompt_mentions_the_brief_only_when_there_is_one(self):
        self.assertIn("docs/sidework/tasks/x.md", sw.default_prompt("x", True))
        self.assertNotIn("tasks/", sw.default_prompt("x", False))
        self.assertIn("docs/sidework/CONVENTIONS.md", sw.default_prompt("x", False))


class Agent(Base):
    def dry(self, task, *extra):
        return tool(self.repo, "agent", task, "--dry-run", *extra)

    def test_dry_run_interactive(self):
        self.start("docs")
        res = self.dry("docs")
        self.assertEqual(res.returncode, 0, res.stderr)
        out = res.stdout
        self.assertIn("command   opencode\n", out)
        self.assertIn("ollama/rutile-main:32k  (base qwen3:14b, context 32768)", out)
        self.assertIn("local-model <local-model@localhost>", out)
        self.assertIn('"tool_call": true', out)
        self.assertIn('"enabled_providers"', out)

    def test_unattended_runs_headless_with_auto_and_a_prompt(self):
        self.start("docs")
        out = self.dry("docs", "--unattended").stdout
        self.assertIn("opencode run --model ollama/rutile-main:32k --title docs --auto", out)
        self.assertIn("Follow docs/sidework/CONVENTIONS.md", out)

    def test_a_custom_prompt_runs_headless_without_auto(self):
        self.start("docs")
        out = self.dry("docs", "--prompt", "fix the typo").stdout
        self.assertIn("opencode run --model", out)
        self.assertIn("'fix the typo'", out)
        self.assertNotIn("--auto", out)

    def test_instructions_include_the_brief_only_when_it_exists_on_the_branch(self):
        wt = self.start("brief")
        cfg = lambda: json.loads(self.dry("brief").stdout.split("config   ", 1)[1])
        self.assertEqual(cfg()["instructions"], ["docs/sidework/CONVENTIONS.md"])
        (wt / "docs" / "sidework" / "tasks").mkdir(parents=True)
        (wt / "docs" / "sidework" / "tasks" / "brief.md").write_text("do the thing\n")
        self.assertEqual(cfg()["instructions"], ["docs/sidework/CONVENTIONS.md", "docs/sidework/tasks/brief.md"])

    def test_the_task_allowlist_reaches_the_edit_permissions(self):
        self.start("narrow", "--path", "widgets/templates/**")
        c = json.loads(self.dry("narrow").stdout.split("config   ", 1)[1])
        self.assertEqual(decide(c["permission"], "edit", "widgets/templates/a.json"), "allow")
        self.assertEqual(decide(c["permission"], "edit", "widgets/spec.json"), "deny")

    def test_tier_and_model_overrides_and_unknown_tier(self):
        self.start("t")
        self.assertIn("ollama/rutile-fast:32k", self.dry("t", "--tier", "fast").stdout)
        self.assertIn("ollama/my:model", self.dry("t", "--model", "my:model").stdout)
        bad = self.dry("t", "--tier", "huge")
        self.assertEqual(bad.returncode, 2)
        self.assertIn("unknown tier", bad.stderr)

    def test_without_a_worktree_it_says_to_start_one(self):
        res = self.dry("ghost")
        self.assertEqual(res.returncode, 2)
        self.assertIn("sidework.py start ghost", res.stderr)

    def run_agent(self, task, *args, path="", host=None, extra_env=None):
        env = dict(GIT_ENV, PATH=path + os.pathsep + "/usr/bin" + os.pathsep + "/bin")
        if host:
            env["OLLAMA_HOST"] = host
        env.update(extra_env or {})
        return subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "agent", task, *args],
                              cwd=self.repo, capture_output=True, text=True, env=env)

    def test_opencode_missing_points_at_the_dev_shell(self):
        self.start("p")
        res = self.run_agent("p", path="")
        self.assertEqual(res.returncode, 2)
        self.assertIn("nix develop .#local-ai", res.stderr)

    def test_opencode_2x_is_refused_because_the_config_schema_differs(self):
        self.start("v2")
        binpath = fake_bin(self.tmp, "opencode", 'echo "2.0.3"\n')
        res = self.run_agent("v2", path=str(binpath))
        self.assertEqual(res.returncode, 2)
        self.assertIn("1.x schema", res.stderr)

    def test_unreachable_ollama_gives_actionable_advice(self):
        self.start("down")
        binpath = fake_bin(self.tmp, "opencode", 'echo "1.19.0"\n')
        res = self.run_agent("down", path=str(binpath), host="127.0.0.1:9")
        self.assertEqual(res.returncode, 2)
        self.assertIn("not reachable", res.stderr)
        self.assertIn("sidework.py serve", res.stderr)

    def test_a_tier_whose_derived_model_is_missing_says_to_prepare_it(self):
        self.start("prep")
        binpath = fake_bin(self.tmp, "opencode", 'echo "1.19.0"\n')
        server, host = fake_ollama(["qwen3:14b"])
        self.addCleanup(server.shutdown)
        res = self.run_agent("prep", path=str(binpath), host=host)
        self.assertEqual(res.returncode, 2)
        self.assertIn("sidework.py prepare --tier main", res.stderr)
        self.assertIn("ollama pull qwen3:14b", res.stderr)

    def test_a_raw_model_that_is_not_pulled_says_to_pull_it(self):
        self.start("raw")
        binpath = fake_bin(self.tmp, "opencode", 'echo "1.19.0"\n')
        server, host = fake_ollama(["other:1b"])
        self.addCleanup(server.shutdown)
        res = self.run_agent("raw", "--model", "my:model", path=str(binpath), host=host)
        self.assertEqual(res.returncode, 2)
        self.assertIn("ollama pull my:model", res.stderr)

    def test_a_ready_setup_execs_opencode_in_the_worktree_with_the_inline_config_and_identity(self):
        wt = self.start("go")
        out = Path(self.tmp) / "out"
        out.mkdir()
        body = ('if [ "$1" = "--version" ]; then echo 1.19.0; exit 0; fi\n'
                f'pwd > {out}/cwd\nprintf "%s\\n" "$@" > {out}/args\n'
                f'printf "%s" "$OPENCODE_CONFIG_CONTENT" > {out}/config\n'
                f'echo "$GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>|$GIT_COMMITTER_NAME" > {out}/ident\n')
        binpath = fake_bin(self.tmp, "opencode", body)
        server, host = fake_ollama(["rutile-main:32k"])
        self.addCleanup(server.shutdown)
        res = self.run_agent("go", "--unattended", path=str(binpath), host=host)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(Path((out / "cwd").read_text().strip()).resolve(), wt.resolve())
        args = (out / "args").read_text().splitlines()
        self.assertEqual(args[:5], ["run", "--model", "ollama/rutile-main:32k", "--title", "go"])
        self.assertIn("--auto", args)
        conf = json.loads((out / "config").read_text())
        self.assertEqual(conf["model"], "ollama/rutile-main:32k")
        self.assertEqual(conf["provider"]["ollama"]["options"]["baseURL"], f"http://{host}/v1")
        self.assertEqual(decide(conf["permission"], "edit", "shell/a.qml"), "deny")
        self.assertEqual((out / "ident").read_text().strip(), "local-model <local-model@localhost>|local-model")


class ModelsCmd(Base):
    def test_reports_pulled_prepared_and_fit(self):
        server, host = fake_ollama(["qwen3:14b", "rutile-main:32k"])
        self.addCleanup(server.shutdown)
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "models"], cwd=self.repo,
                           capture_output=True, text=True, env=dict(GIT_ENV, OLLAMA_HOST=host))
        self.assertEqual(p.returncode, 0, p.stderr)
        lines = {l.split()[0]: l for l in p.stdout.splitlines() if l.split() and l.split()[0] in ("fast", "main", "stretch")}
        self.assertEqual(set(lines), {"fast", "main", "stretch"})
        self.assertIn("fits", lines["main"])
        self.assertIn("pulled, ready", lines["main"])
        self.assertIn("not pulled, not prepared", lines["fast"])
        self.assertIn("SPILLS TO CPU", lines["stretch"])
        self.assertIn("agent model: ollama/rutile-main:32k", p.stdout)
        self.assertIn("agent context 32768", p.stdout)

    def test_when_ollama_is_down_it_still_lists_the_tiers(self):
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "models"], cwd=self.repo,
                           capture_output=True, text=True, env=dict(GIT_ENV, OLLAMA_HOST="127.0.0.1:9"))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("not reachable", p.stdout)
        self.assertIn("qwen3:14b", p.stdout)


class Prepare(Base):
    def run_prepare(self, *args, path="", host=None):
        env = dict(GIT_ENV, PATH=path + os.pathsep + "/usr/bin" + os.pathsep + "/bin")
        if host:
            env["OLLAMA_HOST"] = host
        return subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "prepare", *args],
                              cwd=self.repo, capture_output=True, text=True, env=env)

    def test_dry_run_shows_the_modelfile(self):
        res = self.run_prepare("--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("ollama create rutile-main:32k", res.stdout)
        self.assertIn("FROM qwen3:14b", res.stdout)
        self.assertIn("PARAMETER num_ctx 32768", res.stdout)

    def test_creates_the_derived_model_through_ollama(self):
        out = Path(self.tmp) / "o"
        out.mkdir()
        binpath = fake_bin(self.tmp, "ollama", f'echo "$@" > {out}/args\ncp "$4" {out}/Modelfile\n')
        server, host = fake_ollama(["qwen3:8b"])
        self.addCleanup(server.shutdown)
        res = self.run_prepare("--tier", "fast", path=str(binpath), host=host)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue((out / "args").read_text().startswith("create rutile-fast:32k -f "))
        self.assertEqual((out / "Modelfile").read_text().splitlines()[0], "FROM qwen3:8b")
        self.assertIn("created rutile-fast:32k", res.stdout)

    def test_base_model_must_be_pulled_first(self):
        binpath = fake_bin(self.tmp, "ollama", "exit 0\n")
        server, host = fake_ollama([])
        self.addCleanup(server.shutdown)
        res = self.run_prepare(path=str(binpath), host=host)
        self.assertEqual(res.returncode, 2)
        self.assertIn("ollama pull qwen3:14b", res.stderr)

    def test_unreachable_server_unknown_tier_and_raw_models(self):
        self.assertIn("not reachable", self.run_prepare(host="127.0.0.1:9").stderr)
        self.assertIn("unknown tier", self.run_prepare("--tier", "huge", "--dry-run").stderr)
        self.assertIn("works on tiers", self.run_prepare("--model", "x:1", "--dry-run").stderr)

    def test_ollama_create_failure_is_reported(self):
        binpath = fake_bin(self.tmp, "ollama", "exit 3\n")
        server, host = fake_ollama(["qwen3:14b"])
        self.addCleanup(server.shutdown)
        res = self.run_prepare(path=str(binpath), host=host)
        self.assertEqual(res.returncode, 2)
        self.assertIn("failed", res.stderr)


REAL_OPENCODE = shutil.which("opencode") or os.environ.get("RUTILE_OPENCODE")


@unittest.skipUnless(REAL_OPENCODE, "opencode not found (put it on PATH or set RUTILE_OPENCODE); real-opencode checks SKIPPED")
class RealOpencode(unittest.TestCase):
    """The generated config, checked against the actual opencode binary (`opencode debug ...`)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.proj = Path(self.tmp) / "proj"
        self.proj.mkdir()
        run(["git", "init", "-q", "-b", "main"], self.proj)
        cfg, models = sw.load_config(), sw.load_models()
        self.conf = sw.opencode_config(cfg, models, "rutile-main:32k", 0.6, cfg["local_owned"],
                                       ["docs/sidework/CONVENTIONS.md"])
        home = Path(self.tmp) / "home"
        self.env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "c"), XDG_DATA_HOME=str(home / "d"),
                        XDG_CACHE_HOME=str(home / "k"), XDG_STATE_HOME=str(home / "s"),
                        OPENCODE_CONFIG_CONTENT=json.dumps(self.conf))

    def debug(self, *args):
        p = subprocess.run([REAL_OPENCODE, "debug", *args], cwd=self.proj, capture_output=True, text=True,
                           env=self.env, timeout=120)
        self.assertEqual(p.returncode, 0, p.stderr[-1500:])
        return json.loads(p.stdout[p.stdout.index("{"):])

    def test_version_is_the_1x_line_the_config_targets(self):
        out = subprocess.run([REAL_OPENCODE, "--version"], capture_output=True, text=True, env=self.env).stdout.strip()
        self.assertTrue(out.startswith("1."), f"opencode {out}: the config schema targets 1.x")

    def test_the_resolved_config_keeps_our_provider_model_and_limits(self):
        d = self.debug("config")
        self.assertEqual(d["model"], "ollama/rutile-main:32k")
        self.assertEqual(d["enabled_providers"], ["ollama"])
        m = d["provider"]["ollama"]["models"]["rutile-main:32k"]
        self.assertIs(m["tool_call"], True)
        self.assertEqual(m["limit"], {"context": 32768, "output": 8192})

    def test_a_project_opencode_json_cannot_override_the_inline_settings(self):
        (self.proj / "opencode.json").write_text(json.dumps({
            "model": "openai/gpt-5", "enabled_providers": ["openai"], "share": "auto", "autoupdate": True,
            "permission": {"webfetch": "allow", "external_directory": {"*": "allow"}, "bash": {"git push*": "allow"}}}))
        d = self.debug("config")
        self.assertEqual(d["model"], "ollama/rutile-main:32k")
        self.assertEqual(d["enabled_providers"], ["ollama"])
        self.assertEqual((d["share"], d["autoupdate"]), ("disabled", False))
        self.assertEqual(d["permission"]["webfetch"], "deny")
        self.assertEqual(d["permission"]["external_directory"], {"*": "deny"})
        self.assertEqual(d["permission"]["bash"]["git push*"], "deny")

    def test_effective_rules_decide_the_sample_actions_as_intended(self):
        agent = self.debug("agent", "build")
        rules = agent["permission"]
        for kind, value, want in RULES_SAMPLE:
            action = None
            for r in rules:
                if r["permission"] == kind and wildcard(r["pattern"]).match(value):
                    action = r["action"]
            self.assertEqual(action, want, f"{kind} {value}")

    def test_a_deliberately_unknown_key_is_what_the_binary_reports_so_the_check_is_meaningful(self):
        self.env["OPENCODE_CONFIG_CONTENT"] = json.dumps({**self.conf, "provider": {"ollama": {"models": "not-an-object"}}})
        p = subprocess.run([REAL_OPENCODE, "debug", "config"], cwd=self.proj, capture_output=True, text=True,
                           env=self.env, timeout=120)
        self.assertTrue(p.returncode != 0 or "not-an-object" in p.stdout, "opencode accepted an invalid provider block silently")


class Serve(Base):
    def test_dry_run_shows_the_command_and_server_settings(self):
        res = tool(self.repo, "serve", "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("ollama serve", res.stdout)
        for want in ("OLLAMA_FLASH_ATTENTION=1", "OLLAMA_KV_CACHE_TYPE=q8_0", "OLLAMA_CONTEXT_LENGTH=32768", "OLLAMA_HOST="):
            self.assertIn(want, res.stdout)

    def test_already_running_is_not_started_twice(self):
        server, host = fake_ollama([])
        self.addCleanup(server.shutdown)
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "serve"], cwd=self.repo,
                           capture_output=True, text=True, env=dict(GIT_ENV, OLLAMA_HOST=host))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("already running", p.stdout)

    def test_missing_binary_points_at_the_dev_shell(self):
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "serve"], cwd=self.repo,
                           capture_output=True, text=True, env=dict(GIT_ENV, OLLAMA_HOST="127.0.0.1:9", PATH=""))
        self.assertEqual(p.returncode, 2)
        self.assertIn("nix develop .#local-ai", p.stderr)


def fake_ollama(names):
    body = json.dumps({"models": [{"name": n} for n in names]}).encode()

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"127.0.0.1:{server.server_address[1]}"


class OllamaTags(unittest.TestCase):
    def test_tags_and_unreachable(self):
        server, host = fake_ollama(["a:1", "b:2"])
        self.addCleanup(server.shutdown)
        self.assertEqual(sw.ollama_tags(host), ["a:1", "b:2"])
        self.assertIsNone(sw.ollama_tags("127.0.0.1:9", timeout=1))


if __name__ == "__main__":
    unittest.main()
