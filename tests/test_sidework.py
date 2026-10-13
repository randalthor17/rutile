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

    def test_hook_marks_in_the_docs_match_the_code(self):
        doc = (ROOT / "docs" / "sidework.md").read_text()
        self.assertIn("--git-commit-verify", doc)
        self.assertIn("--git-commit-verify", " ".join(sw.aider_command(None, "x:1b")))
        self.assertIn("always forbidden", doc.lower().replace("*", ""))


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


class Agent(Base):
    def test_dry_run_shows_model_context_identity_and_environment(self):
        self.start("docs")
        (self.repo / "docs" / "sidework" / "tasks").mkdir(parents=True, exist_ok=True)
        res = tool(self.repo, "agent", "docs", "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        out = res.stdout
        self.assertIn("--model ollama_chat/qwen2.5-coder:14b", out)
        self.assertIn("--read docs/sidework/CONVENTIONS.md", out)
        self.assertIn("--git-commit-verify", out)
        self.assertIn("num_ctx: 16384".replace(": ", ": "), out.replace("num_ctx: ", "num_ctx: "))
        self.assertIn("local-model <local-model@localhost>", out)
        self.assertIn("OLLAMA_KV_CACHE_TYPE=q8_0", out)
        self.assertIn("OLLAMA_FLASH_ATTENTION=1", out)

    def test_tier_and_model_overrides_and_unknown_tier(self):
        self.start("t")
        self.assertIn("ollama_chat/qwen2.5-coder:7b", tool(self.repo, "agent", "t", "--tier", "fast", "--dry-run").stdout)
        self.assertIn("ollama_chat/my:model", tool(self.repo, "agent", "t", "--model", "my:model", "--dry-run").stdout)
        bad = tool(self.repo, "agent", "t", "--tier", "huge", "--dry-run")
        self.assertEqual(bad.returncode, 2)
        self.assertIn("unknown tier", bad.stderr)

    def test_a_task_brief_is_added_when_it_exists_on_the_branch(self):
        wt = self.start("brief")
        self.assertNotIn("tasks/brief.md", tool(self.repo, "agent", "brief", "--dry-run").stdout)
        (wt / "docs" / "sidework" / "tasks").mkdir(parents=True)
        (wt / "docs" / "sidework" / "tasks" / "brief.md").write_text("do the thing\n")
        self.assertIn("--read docs/sidework/tasks/brief.md", tool(self.repo, "agent", "brief", "--dry-run").stdout)

    def test_without_a_worktree_it_says_to_start_one(self):
        res = tool(self.repo, "agent", "ghost", "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertIn("sidework.py start ghost", res.stderr)

    def test_unreachable_ollama_gives_actionable_advice(self):
        self.start("down")
        env = dict(GIT_ENV, OLLAMA_HOST="127.0.0.1:9")
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "agent", "down"], cwd=self.repo,
                           capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 2)
        self.assertIn("not reachable", p.stderr)
        self.assertIn("ollama serve", p.stderr)

    def test_unpulled_model_says_which_to_pull(self):
        self.start("pull")
        server, host = fake_ollama(["some-other:1b"])
        self.addCleanup(server.shutdown)
        env = dict(GIT_ENV, OLLAMA_HOST=host)
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "agent", "pull"], cwd=self.repo,
                           capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 2)
        self.assertIn("ollama pull qwen2.5-coder:14b", p.stderr)

    def test_models_command_reports_pulled_and_fit(self):
        server, host = fake_ollama(["qwen2.5-coder:14b"])
        self.addCleanup(server.shutdown)
        env = dict(GIT_ENV, OLLAMA_HOST=host)
        p = subprocess.run([sys.executable, str(self.repo / "tools" / "sidework.py"), "models"], cwd=self.repo,
                           capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        lines = {l.split()[0]: l for l in p.stdout.splitlines() if l.split() and l.split()[0] in ("fast", "main", "general", "stretch")}
        self.assertIn(" pulled", lines["main"].replace("not pulled", "NOPE") if "not pulled" in lines["main"] else lines["main"])
        self.assertNotIn("not pulled", lines["main"])
        self.assertIn("not pulled", lines["fast"])
        self.assertIn("SPILLS TO CPU", lines["stretch"])
        self.assertIn("fits", lines["main"])


class Serve(Base):
    def test_dry_run_shows_the_command_and_server_settings(self):
        res = tool(self.repo, "serve", "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("ollama serve", res.stdout)
        for want in ("OLLAMA_FLASH_ATTENTION=1", "OLLAMA_KV_CACHE_TYPE=q8_0", "OLLAMA_CONTEXT_LENGTH=16384", "OLLAMA_HOST="):
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
