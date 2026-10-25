#!/usr/bin/env python3
"""Run a local model on side tasks without it ever clashing with the main line of work.

The idea is to make merge conflicts impossible, not just unlikely: the local model works on a
`local/<task>` branch in its own git worktree, and may only change paths listed in
tools/ownership.json (`local_owned`). A pre-commit hook enforces that at commit time, so even an
agent that wanders cannot commit outside its area. Claude's sessions leave those paths alone.

    sidework.py start TASK [--path GLOB ...] [--dir DIR] [--base REF]
                                   create branch local/TASK in a new worktree, install the guard
    sidework.py prepare [--tier T]  bake the context length into a derived Ollama model
    sidework.py agent TASK [--tier T | --model NAME] [--unattended] [--prompt TEXT] [--dry-run]
                                   run opencode in that worktree with a local Ollama model
    sidework.py check [TASK] [--run-checks]
                                   verify a branch only touches allowed paths and passes its brief's
                                   acceptance check (and `make check`)
    sidework.py merge-check [TASK] dry-run the merge into main; fails on any conflict
    sidework.py merge TASK [--accept-failing REASON]
                                   merge into main, only if check and merge-check pass; REASON merges a
                                   failing branch anyway and records it as a TODO in the merge commit
    sidework.py close TASK [--force]
                                   after the merge: remove the worktree, the branch and its allowlist
    sidework.py bundle TASK [--out FILE]
                                   a git bundle of the branch's commits, to hand over
    sidework.py status             list local/* branches and whether each is clean to merge
    sidework.py models             the model tiers and which are pulled in Ollama
    sidework.py serve [--dry-run]  start `ollama serve` with the settings in tools/local_models.json
    sidework.py guard              (used by the pre-commit hook: paths, then the acceptance check)

Every task brief declares its acceptance check as the first code block under `## Acceptance`. It is read
from the MAIN checkout's brief, never the worktree's, and run on an exact copy of what is being committed
or merged, so a commit or merge of work that fails its own brief is refused.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASK_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")


class SideworkError(Exception):
    pass


# ---------------------------------------------------------------- config and path matching

def load_config(root=None):
    return json.loads(((root or ROOT) / "tools" / "ownership.json").read_text())


def load_models(root=None):
    return json.loads(((root or ROOT) / "tools" / "local_models.json").read_text())


def glob_to_regex(pattern):
    """`*` stays within a directory, `**` crosses directories, `?` is one character."""
    out, i = [], 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
                continue
            if pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def matches(path, patterns):
    return any(glob_to_regex(p).match(path) for p in patterns)


def violations(files, allowed, cfg):
    """Paths that a local branch may not touch: forbidden always, otherwise anything not allowed."""
    bad = []
    for f in files:
        if matches(f, cfg["always_forbidden"]):
            bad.append((f, "always forbidden"))
        elif not matches(f, allowed):
            bad.append((f, "outside the allowed paths"))
    return bad


# ---------------------------------------------------------------- git helpers

def git(*args, cwd=None, check=True):
    proc = subprocess.run(["git", *args], cwd=cwd or ROOT, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise SideworkError(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc


def common_dir(cwd=None):
    out = git("rev-parse", "--git-common-dir", cwd=cwd).stdout.strip()
    p = Path(out)
    return p if p.is_absolute() else Path(cwd or ROOT) / p


def state_file(branch, cwd=None):
    return common_dir(cwd) / "rutile-sidework" / (branch.replace("/", "__") + ".json")


def allowed_paths(branch, cfg, cwd=None):
    f = state_file(branch, cwd)
    if f.exists():
        return json.loads(f.read_text())["paths"]
    return cfg["local_owned"]


def current_branch(cwd=None):
    proc = git("symbolic-ref", "--short", "-q", "HEAD", cwd=cwd, check=False)
    return proc.stdout.strip()


def parse_name_status_z(raw):
    """All paths from `git diff --name-status -z` (both sides of renames and copies)."""
    toks = [t for t in raw.split("\0") if t != ""]
    paths, i = [], 0
    while i < len(toks):
        status = toks[i]
        n = 2 if status[0] in "RC" else 1
        paths.extend(toks[i + 1:i + 1 + n])
        i += 1 + n
    return paths


def branch_name(task, cfg):
    if not TASK_RE.match(task):
        raise SideworkError(f"task name {task!r} must match {TASK_RE.pattern}")
    return cfg["branch_prefix"] + task


def branch_exists(branch, cwd=None):
    return git("rev-parse", "--verify", "-q", f"refs/heads/{branch}", cwd=cwd, check=False).returncode == 0


def worktree_of(branch, cwd=None):
    out = git("worktree", "list", "--porcelain", cwd=cwd).stdout
    cur = None
    for line in out.splitlines():
        if line.startswith("worktree "):
            cur = line[len("worktree "):]
        elif line.startswith("branch ") and line[len("branch "):] == f"refs/heads/{branch}":
            return Path(cur)
    return None


# ---------------------------------------------------------------- acceptance checks

ACCEPT_LINES = 40        # how much of a failing check's output to show; a model reads the first errors


def task_of(branch, cfg, cwd=None):
    f = state_file(branch, cwd)
    if f.exists():
        return json.loads(f.read_text())["task"]
    return branch[len(cfg["branch_prefix"]):]


def acceptance_commands(task, root=None):
    """The commands in the first code block under `## Acceptance` of the task's brief, or [] if none.

    Always the main checkout's brief (`root`), never the copy in the worktree being checked.
    """
    brief = (root or ROOT) / "docs" / "sidework" / "tasks" / f"{task}.md"
    if not brief.exists():
        return []
    m = re.search(r"^## Acceptance\n(.*?)(?=^## |\Z)", brief.read_text(), re.S | re.M)
    block = re.search(r"^```[a-z]*\n(.*?)^```", m.group(1), re.S | re.M) if m else None
    if not block:
        return []
    return [line.strip() for line in block.group(1).splitlines() if line.strip() and not line.strip().startswith("#")]


def run_acceptance(commands, tree):
    """(passed, output) of running the commands in directory `tree`, a copy of the work being judged."""
    out, ok = [], True
    for cmd in commands:
        proc = subprocess.run(cmd, shell=True, cwd=tree, capture_output=True, text=True, stdin=subprocess.DEVNULL,
                              env=dict(os.environ, PWD=str(tree)))
        out.append(f"$ {cmd}\n{proc.stdout}{proc.stderr}")
        ok = ok and proc.returncode == 0
    return ok, "".join(out)


def export_tree(ref, dest, cwd=None):
    """Write the tree of a commit or tree object `ref` to `dest`."""
    archive = subprocess.run(["git", "archive", ref], cwd=cwd or ROOT, capture_output=True, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)


def merged_tree(branch, cfg, dest):
    """What the base branch would look like after merging `branch`: the base's tools, the branch's work.

    Judging the branch's own tip instead would use whatever tools it was started with (possibly none).
    """
    proc = git("merge-tree", "--write-tree", cfg["base"], branch, check=False)
    if proc.returncode != 0:
        raise SideworkError(f"{branch} does not merge cleanly into {cfg['base']}; see `sidework.py merge-check`")
    export_tree(proc.stdout.split()[0], dest)


def staged_onto_base(repo, allowed, cfg, dest):
    """The base branch with the allowed paths replaced by what is staged in `repo` (the commit being made)."""
    export_tree(cfg["base"], dest)
    for f in Path(dest).rglob("*"):
        if f.is_file() and matches(str(f.relative_to(dest)), allowed):
            f.unlink()
    with tempfile.TemporaryDirectory() as staged:
        git("checkout-index", "--all", f"--prefix={staged}/", cwd=repo)
        for f in Path(staged).rglob("*"):
            rel = str(f.relative_to(staged))
            if f.is_file() and matches(rel, allowed):
                (Path(dest) / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, Path(dest) / rel)


def shorten(text, lines=ACCEPT_LINES):
    rows = text.rstrip().splitlines()
    return "\n".join(rows[:lines] + ([f"... {len(rows) - lines} more line(s)"] if len(rows) > lines else []))


def branch_acceptance(branch, cfg):
    """(commands, passed, output) for the tip of `branch`; passed is None when the brief has no check."""
    commands = acceptance_commands(task_of(branch, cfg))
    if not commands:
        return commands, None, ""
    with tempfile.TemporaryDirectory() as d:
        merged_tree(branch, cfg, d)
        ok, output = run_acceptance(commands, Path(d))
    return commands, ok, output


# ---------------------------------------------------------------- commands

def cmd_guard(args):
    # The hook runs this file from the MAIN checkout (core.hooksPath is absolute), so the rules in
    # ownership.json are the main checkout's, never the copy inside the worktree being policed.
    # Git state, however, is the worktree's: the current directory.
    here = Path.cwd()
    cfg = load_config()
    branch = current_branch(here)
    if not branch.startswith(cfg["branch_prefix"]):
        return 0
    raw = git("diff", "--cached", "--name-status", "-z", cwd=here).stdout
    allowed = allowed_paths(branch, cfg, here)
    bad = violations(parse_name_status_z(raw), allowed, cfg)
    if bad:
        print(f"sidework: commit rejected on {branch}: it touches paths this branch does not own", file=sys.stderr)
        for path, why in bad:
            print(f"  {path}  ({why})", file=sys.stderr)
        print("Allowed: " + ", ".join(allowed), file=sys.stderr)
        print("Unstage those files (git restore --staged <path>) and commit only your own area.", file=sys.stderr)
        return 1
    commands = acceptance_commands(task_of(branch, cfg, here))
    if not commands:
        return 0
    with tempfile.TemporaryDirectory() as d:
        staged_onto_base(here, allowed, cfg, d)
        ok, output = run_acceptance(commands, Path(d))
    if ok:
        return 0
    print(f"sidework: commit rejected on {branch}: the task's acceptance check fails on what you staged.",
          file=sys.stderr)
    print(shorten(output), file=sys.stderr)
    print("Fix the first problem above, run the same command, and commit again when it passes.", file=sys.stderr)
    return 1


def cmd_start(args):
    cfg = load_config()
    branch = branch_name(args.task, cfg)
    if branch_exists(branch):
        raise SideworkError(f"branch {branch} already exists")
    base = args.base or cfg["base"]
    dest = Path(args.dir) if args.dir else ROOT.parent / f"{ROOT.name}-local-{args.task}"
    git("worktree", "add", "-b", branch, str(dest), base)
    git("config", "core.hooksPath", str(ROOT / "tools" / "hooks"))   # absolute, in the main checkout
    paths = args.path or cfg["local_owned"]
    f = state_file(branch)
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps({"task": args.task, "paths": paths}, indent=2) + "\n")
    print(f"branch   {branch}")
    print(f"worktree {dest}")
    print(f"allowed  {', '.join(paths)}")
    print(f"next     python3 tools/sidework.py agent {args.task}")
    return 0


def changed_files(branch, base, cwd=None):
    raw = git("diff", "--name-status", "-z", f"{base}...{branch}", cwd=cwd).stdout
    return parse_name_status_z(raw)


def worktree_leftovers(wt, allowed, cfg):
    """Uncommitted changes in a worktree as (path, git status, outside the allowed paths).

    They are not part of the branch, so they never merge, but the next agent session sees them as if
    they were the work (a model once left a rewritten flake.nix and a virtualenv behind).
    """
    raw = git("status", "--porcelain", "-z", "--untracked-files=normal", cwd=wt).stdout
    toks = [t for t in raw.split("\0") if t]
    out, i = [], 0
    while i < len(toks):
        status, path = toks[i][:2], toks[i][3:]
        i += 2 if status[0] in "RC" else 1        # a rename is followed by its old path
        out.append((path, status.strip(), bool(violations([path.rstrip("/")], allowed, cfg))))
    return out


def print_leftovers(wt, leftovers, out):
    print(f"uncommitted in {wt} (not on the branch, so it will not merge):", file=out)
    for path, status, outside in leftovers:
        print(f"  {status:2s} {path}" + ("  (outside the allowed paths)" if outside else ""), file=out)
    if any(outside for _, _, outside in leftovers):
        print("  clean up what is outside the allowed paths before the next session, e.g. "
              f"git -C {wt} restore <file>, or delete stray untracked files", file=out)


def resolve_branch(task, cfg):
    if task:
        return branch_name(task, cfg)
    cur = current_branch()
    if cur.startswith(cfg["branch_prefix"]):
        return cur
    raise SideworkError("give a TASK, or run from inside a local/* worktree")


def cmd_check(args):
    cfg = load_config()
    branch = resolve_branch(args.task, cfg)
    if not branch_exists(branch):
        raise SideworkError(f"no such branch {branch}")
    files = changed_files(branch, cfg["base"])
    bad = violations(files, allowed_paths(branch, cfg), cfg)
    print(f"{branch}: {len(files)} changed file(s)")
    for f in files:
        print(f"  {f}")
    if bad:
        print("VIOLATIONS:", file=sys.stderr)
        for path, why in bad:
            print(f"  {path}  ({why})", file=sys.stderr)
        return 1
    wt = worktree_of(branch)
    leftovers = worktree_leftovers(wt, allowed_paths(branch, cfg), cfg) if wt else []
    if leftovers:
        print_leftovers(wt, leftovers, sys.stdout)
    commands, accepted, output = branch_acceptance(branch, cfg)
    if accepted is None:
        print("acceptance: none declared in the brief (nothing checks this branch's content)")
    elif not accepted:
        print(f"acceptance: FAILED for {branch} merged into {cfg['base']}")
        print(shorten(output))
        return 1
    else:
        print("acceptance: passed (" + "; ".join(commands) + ")")
    if args.run_checks:
        if wt is None:
            raise SideworkError(f"{branch} has no worktree to run `make check` in")
        print("running make check ...")
        code = subprocess.run(["make", "check"], cwd=wt).returncode
        if code != 0:
            print("make check failed", file=sys.stderr)
            return 1
    print("ok: only allowed paths changed, and the acceptance check passes" if accepted
          else "ok: only allowed paths changed")
    return 0


def merge_conflicts(branch, into):
    """(clean, conflicted files) from a dry-run merge that touches nothing."""
    proc = git("merge-tree", "--write-tree", "--name-only", into, branch, check=False)
    if proc.returncode == 0:
        return True, []
    if proc.returncode != 1:
        raise SideworkError(f"git merge-tree failed (needs git 2.38+): {proc.stderr.strip()}")
    lines = proc.stdout.splitlines()
    files = []
    for line in lines[1:]:
        if not line.strip():
            break
        files.append(line.strip())
    return False, files


def cmd_merge_check(args):
    cfg = load_config()
    branch = resolve_branch(args.task, cfg)
    clean, files = merge_conflicts(branch, cfg["base"])
    if clean:
        print(f"{branch} merges into {cfg['base']} cleanly")
        return 0
    print(f"{branch} CONFLICTS with {cfg['base']}:", file=sys.stderr)
    for f in files:
        print(f"  {f}", file=sys.stderr)
    return 1


def cmd_merge(args):
    """Merge a local branch, refusing anything `check` or `merge-check` would fail, unless told why."""
    cfg = load_config()
    branch = branch_name(args.task, cfg)
    if not branch_exists(branch):
        raise SideworkError(f"no such branch {branch}")
    if current_branch() != cfg["base"]:
        raise SideworkError(f"run merge from the main checkout on {cfg['base']}")
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        raise SideworkError("the main checkout has uncommitted changes; commit or stash them first")
    bad = violations(changed_files(branch, cfg["base"]), allowed_paths(branch, cfg), cfg)
    if bad:
        raise SideworkError(f"{branch} touches paths it does not own ({', '.join(p for p, _ in bad)}); "
                            "see `sidework.py check`. Never merged, not even with --accept-failing")
    clean, files = merge_conflicts(branch, cfg["base"])
    if not clean:
        raise SideworkError(f"{branch} conflicts with {cfg['base']} in: {', '.join(files)}")
    commands, accepted, output = branch_acceptance(branch, cfg)
    if accepted is False and not args.accept_failing:
        print(shorten(output), file=sys.stderr)
        raise SideworkError(f"{branch} fails its acceptance check (above). Fix it on the branch, or merge it as a "
                            "known-broken draft with --accept-failing \"why\"")
    message = f"Merge {branch}"
    if accepted is False:
        message += (f" (fails its acceptance check)\n\nTODO: {args.accept_failing}\n\n"
                    f"Acceptance output at merge time:\n{shorten(output, 25)}")
    elif accepted is None:
        message += "\n\nThe brief declares no acceptance check; nothing verified the content."
    git("merge", "--no-ff", branch, "-m", message)
    print(f"merged {branch} into {cfg['base']}" + (" AS A FAILING DRAFT (TODO recorded in the commit)"
                                                   if accepted is False else ""))
    print(f"next     python3 tools/sidework.py close {args.task}")
    return 0


def cmd_close(args):
    """Remove a merged task's worktree, branch and allowlist, which reopens its paths to the main line."""
    cfg = load_config()
    branch = branch_name(args.task, cfg)
    if not branch_exists(branch):
        raise SideworkError(f"no such branch {branch}")
    if git("merge-base", "--is-ancestor", branch, cfg["base"], check=False).returncode != 0:
        raise SideworkError(f"{branch} has commits that are not in {cfg['base']}; merge it first (or delete it by hand)")
    wt = worktree_of(branch)
    if wt is not None:
        leftovers = worktree_leftovers(wt, allowed_paths(branch, cfg), cfg)
        if leftovers and not args.force:
            print_leftovers(wt, leftovers, sys.stderr)
            raise SideworkError("the worktree has uncommitted files (above); they would be deleted. "
                                "Rerun with --force once you are sure they are not needed")
        git("worktree", "remove", *(["--force"] if args.force else []), str(wt))
    git("branch", "-d", branch)
    state_file(branch).unlink(missing_ok=True)
    print(f"closed {branch}" + (f" and removed {wt}" if wt else ""))
    return 0


def cmd_bundle(args):
    cfg = load_config()
    branch = branch_name(args.task, cfg)
    if not branch_exists(branch):
        raise SideworkError(f"no such branch {branch}")
    out = Path(args.out) if args.out else Path(f"{args.task}.bundle")
    git("bundle", "create", str(out), f"{cfg['base']}..{branch}")
    git("bundle", "verify", str(out))
    print(out)
    return 0


def cmd_status(args):
    cfg = load_config()
    refs = git("for-each-ref", "--format=%(refname:short)", f"refs/heads/{cfg['branch_prefix']}").stdout.split()
    if not refs:
        print("no local/* branches")
        return 0
    for br in refs:
        ahead = git("rev-list", "--count", f"{cfg['base']}..{br}").stdout.strip()
        bad = violations(changed_files(br, cfg["base"]), allowed_paths(br, cfg), cfg)
        clean, _ = merge_conflicts(br, cfg["base"])
        wt = worktree_of(br)
        stray = sum(1 for *_, outside in worktree_leftovers(wt, allowed_paths(br, cfg), cfg) if outside) if wt else 0
        print(f"{br:30s} {ahead:>3} commit(s)  paths:{'OK' if not bad else 'VIOLATED'}  "
              f"merge:{'clean' if clean else 'CONFLICT'}  {wt or '(no worktree)'}"
              + (f"  ({stray} stray uncommitted file(s): see `check`)" if stray else ""))
    return 0


# ---------------------------------------------------------------- models and the agent

def ollama_tags(host, timeout=3):
    """Names of pulled models, or None if the server cannot be reached."""
    url = host if host.startswith("http") else f"http://{host}"
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/api/tags", timeout=timeout) as r:
            return [m["name"] for m in json.loads(r.read().decode())["models"]]
    except (urllib.error.URLError, OSError, ValueError, KeyError):
        return None


def fits(tier, models):
    need = tier["approx_gb"] + models["kv_cache_overhead_gb"]
    return need <= models["vram_gb"], need


def host_of(models):
    return os.environ.get("OLLAMA_HOST") or models["ollama_host"]


def cmd_models(args):
    m = load_models()
    host = host_of(m)
    pulled = ollama_tags(host)
    print(f"Ollama at {host}: " + ("not reachable" if pulled is None else f"{len(pulled)} model(s) pulled"))
    print(f"GPU memory budget {m['vram_gb']} GB, agent context {m['context']}, default tier {m['default_tier']}\n")
    for name, t in m["tiers"].items():
        ok, need = fits(t, m)
        have = "pulled" if pulled and t["tag"] in pulled else "not pulled"
        derived = derived_name(name, m)
        ready = "ready" if pulled and derived in pulled else "not prepared"
        print(f"{name:8s} {t['tag']:18s} ~{need:4.1f} GB needed  {'fits' if ok else 'SPILLS TO CPU':13s} {have}, {ready}")
        print(f"         {t['note']}")
        print(f"         agent model: ollama/{derived}")
    return 0


def cmd_serve(args):
    models = load_models()
    host = host_of(models)
    env = dict(os.environ)
    env.update(models.get("env", {}))
    env["OLLAMA_HOST"] = host
    cmd = ["ollama", "serve"]
    if args.dry_run:
        print("command ", " ".join(cmd))
        print("env     ", ", ".join(f"{k}={env[k]}" for k in sorted([*models.get("env", {}), "OLLAMA_HOST"])))
        return 0
    if ollama_tags(host) is not None:
        print(f"Ollama is already running at {host}; nothing to do")
        return 0
    if shutil.which("ollama") is None:
        raise SideworkError("`ollama` is not on PATH: use `nix develop .#local-ai`, or enable the NixOS service "
                            "(see docs/sidework.md)")
    os.execvpe(cmd[0], cmd, env)
    return 0  # unreachable


def glob_for_opencode(pattern):
    """opencode permission globs: `*` matches any characters including `/`, so `**` becomes `*`.

    A single `*` there also crosses directories, i.e. slightly wider than ours. That is acceptable
    because this layer is advisory; the commit guard and `check` use the exact patterns.
    """
    return pattern.replace("**/", "*").replace("**", "*")


# bash commands the local agent may never run. Matched as parsed commands (last matching rule wins).
BASH_DENY = [
    "git push*", "git remote*", "git config*", "git worktree*", "git clone*", "git fetch*", "git pull*",
    "git commit*--no-verify*", "git commit* -n *", "git commit* -n",
    "sudo *", "su *", "rm -rf /*", "rm -rf ~*", "curl *", "wget *", "ssh *", "scp *", "nc *",
]


# Tools the local agent never gets. `execute` runs JavaScript that can call `fetch` and opencode's own
# worktree tools, which ask for no permission: a model once used it to make a stray worktree.
DENIED_TOOLS = ["execute", "webfetch", "websearch", "external_directory", "doom_loop"]


def rule(action, resource, effect):
    return {"action": action, "resource": resource, "effect": effect}


def derived_name(tier_name, models):
    return f"{models['derived_prefix']}{tier_name}:{models['context'] // 1024}k"


def modelfile_text(tag, models, temperature):
    return f"FROM {tag}\nPARAMETER num_ctx {models['context']}\nPARAMETER temperature {temperature}\n"


def opencode_config(cfg, models, model_name, temperature, allowed, instructions):
    """The inline config handed to opencode through OPENCODE_CONFIG_CONTENT (opencode 2.x schema).

    It is passed inline because opencode merges it after any project opencode.json, and permission
    rules are an ordered list where the last match wins: every action we restrict starts with a
    catch-all rule of ours, so nothing a file in the worktree adds can widen it.
    """
    host = host_of(models)
    base = host if host.startswith("http") else f"http://{host}"
    rules = [rule("edit", "*", "deny")]
    rules += [rule("edit", glob_for_opencode(pat), "allow") for pat in allowed]
    # the guard and the config are never editable, whatever the allowlist says
    rules += [rule("edit", glob_for_opencode(pat), "deny") for pat in cfg["always_forbidden"]]
    rules.append(rule("shell", "*", "allow"))
    rules += [rule("shell", pat, "deny") for pat in BASH_DENY]
    rules += [rule(action, "*", "deny") for action in DENIED_TOOLS]
    return {
        "$schema": "https://opencode.ai/config.json",
        "model": f"ollama/{model_name}",
        "update": "disable",
        "share": "disabled",
        "snapshots": False,                   # the branch's own commits are the history
        "websearch": False,
        "instructions": instructions,
        # never fall back to a cloud provider
        "policies": [
            {"action": "provider.use", "resource": "*", "effect": "deny"},
            {"action": "provider.use", "resource": "ollama", "effect": "allow"},
        ],
        "providers": {
            "ollama": {
                "name": "Ollama (local)",
                # without a package opencode 2.x refuses the model ("Unsupported package")
                "package": "@ai-sdk/openai-compatible",
                "settings": {"baseURL": base + "/v1", "apiKey": "ollama"},
                "models": {
                    model_name: {
                        "name": model_name,
                        # without this opencode sends no tools and the agent can do nothing
                        "capabilities": {"tools": True},
                        "limit": {"context": models["context"], "output": models["output_tokens"]},
                        "body": {"temperature": temperature},
                    }
                },
            }
        },
        "permissions": rules,
        "compaction": {"auto": True},
    }


def agent_env(cfg, models, base_env, config):
    env = dict(base_env)
    ident = cfg["identity"]
    for who in ("AUTHOR", "COMMITTER"):
        env[f"GIT_{who}_NAME"] = ident["name"]
        env[f"GIT_{who}_EMAIL"] = ident["email"]
    env["OPENCODE_CONFIG_CONTENT"] = json.dumps(config)
    # Not OPENCODE_DISABLE_PROJECT_CONFIG: in 2.1.1 it also drops AGENTS.md and our `instructions`.
    return env


def opencode_version():
    """(major, text) of the installed opencode, or None if it is not installed."""
    exe = shutil.which("opencode")
    if exe is None:
        return None
    try:
        out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return (0, "unknown")
    m = re.search(r"(\d+)\.", out)
    return (int(m.group(1)) if m else 0, out or "unknown")


def default_prompt(task, has_brief):
    brief = f"Read docs/sidework/tasks/{task}.md and complete the task it describes. " if has_brief else ""
    return (brief + "Follow docs/sidework/CONVENTIONS.md. Work in small commits (one concern each, imperative "
            "one-line messages). Run the acceptance checks from the brief after each change and fix failures "
            "before moving on. Stop and explain if the task needs a file you may not edit. When finished, "
            "summarize what you changed and anything you are unsure about.")


def resolve_model(args, models):
    """(model name used with opencode, base tag, temperature, tier name or None)."""
    if args.model:
        return args.model, args.model, 0.6, None
    tier_name = args.tier or models["default_tier"]
    if tier_name not in models["tiers"]:
        raise SideworkError(f"unknown tier {tier_name!r}; choose from {', '.join(models['tiers'])}")
    t = models["tiers"][tier_name]
    return derived_name(tier_name, models), t["tag"], t["temperature"], tier_name


def cmd_prepare(args):
    models = load_models()
    name, tag, temperature, tier = resolve_model(args, models)
    if tier is None:
        raise SideworkError("prepare works on tiers; use --tier")
    text = modelfile_text(tag, models, temperature)
    if args.dry_run:
        print(f"ollama create {name} -f <Modelfile>")
        print(text, end="")
        return 0
    pulled = ollama_tags(host_of(models))
    if pulled is None:
        raise SideworkError(f"Ollama is not reachable at {host_of(models)}; start it with `sidework.py serve` first")
    if tag not in pulled:
        raise SideworkError(f"{tag} is not pulled yet: run `ollama pull {tag}` first")
    if shutil.which("ollama") is None:
        raise SideworkError("`ollama` is not on PATH: use `nix develop .#local-ai`")
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        mf = Path(d) / "Modelfile"
        mf.write_text(text)
        env = dict(os.environ, OLLAMA_HOST=host_of(models))
        proc = subprocess.run(["ollama", "create", name, "-f", str(mf)], env=env)
    if proc.returncode != 0:
        raise SideworkError(f"`ollama create {name}` failed")
    print(f"created {name} (context {models['context']})")
    return 0


def cmd_agent(args):
    cfg, models = load_config(), load_models()
    branch = branch_name(args.task, cfg)
    wt = worktree_of(branch)
    if wt is None:
        raise SideworkError(f"no worktree for {branch}; run `sidework.py start {args.task}` first")
    name, tag, temperature, tier = resolve_model(args, models)
    brief = f"docs/sidework/tasks/{args.task}.md"
    has_brief = (wt / brief).exists()
    instructions = ["docs/sidework/CONVENTIONS.md"] + ([brief] if has_brief else [])
    allowed = allowed_paths(branch, cfg, wt)
    config = opencode_config(cfg, models, name, temperature, allowed, instructions)
    prompt = args.prompt or default_prompt(args.task, has_brief)
    # --standalone: opencode 2.x otherwise attaches to its background service, a server started
    # earlier with some other environment, which would never see OPENCODE_CONFIG_CONTENT.
    if args.unattended or args.prompt:
        cmd = ["opencode", "run", "--standalone", "--model", f"ollama/{name}", "--title", args.task]
        if args.unattended:
            cmd.append("--auto")
        cmd.append(prompt)
    else:
        cmd = ["opencode", "--standalone"]
    env = agent_env(cfg, models, os.environ, config)
    if args.dry_run:
        print("cwd      ", wt)
        print("command  ", " ".join(cmd[:-1] + [repr(cmd[-1])] if cmd[:2] == ["opencode", "run"] else cmd))
        print("model    ", f"ollama/{name}  (base {tag}, context {models['context']})")
        print("identity ", f"{env['GIT_AUTHOR_NAME']} <{env['GIT_AUTHOR_EMAIL']}>")
        print("config   ", json.dumps(config, indent=2))
        return 0
    found = opencode_version()
    if found is None:
        raise SideworkError("`opencode` is not on PATH: use `nix develop .#local-ai`")
    if found[0] != 2:
        raise SideworkError(f"opencode {found[1]} found, but the generated config follows the 2.x schema "
                            "(1.x used other keys: provider, permission, tool_call). Use the opencode from "
                            "`nix develop .#local-ai`, or update tools/sidework.py")
    pulled = ollama_tags(host_of(models))
    if pulled is None:
        raise SideworkError(
            f"Ollama is not reachable at {host_of(models)}. Start it (`sidework.py serve`, or enable the NixOS "
            "service from docs/sidework.md) and try again.")
    if tier is not None and name not in pulled:
        raise SideworkError(f"{name} does not exist yet: run `sidework.py prepare --tier {tier}` "
                            f"(after `ollama pull {tag}`)")
    if tier is None and name not in pulled:
        raise SideworkError(f"{name} is not pulled: run `ollama pull {name}`")
    leftovers = [x for x in worktree_leftovers(wt, allowed, cfg) if x[2]]
    if leftovers:
        print_leftovers(wt, leftovers, sys.stderr)
    if cmd[1] == "run" and not sys.stdin.isatty():
        # `opencode run` appends a piped stdin to the prompt and waits for it to end; an inherited open pipe or
        # socket (cron, systemd, an IDE) never ends, so the run would hang before its first request
        null = os.open(os.devnull, os.O_RDONLY)
        os.dup2(null, 0)
        os.close(null)
    os.chdir(wt)
    # opencode takes its directory from $PWD when set, so the inherited one (the main checkout)
    # would put the agent in the wrong tree
    env["PWD"] = str(wt)
    os.execvpe(cmd[0], cmd, env)
    return 0  # unreachable


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("task")
    s.add_argument("--path", action="append")
    s.add_argument("--dir")
    s.add_argument("--base")
    a = sub.add_parser("agent")
    a.add_argument("task")
    a.add_argument("--tier")
    a.add_argument("--model")
    a.add_argument("--prompt", help="run one headless prompt instead of the interactive UI")
    a.add_argument("--unattended", action="store_true",
                   help="run the default task prompt headless and auto-approve anything not explicitly denied")
    a.add_argument("--dry-run", action="store_true")
    pr = sub.add_parser("prepare")
    pr.add_argument("--tier")
    pr.add_argument("--model")
    pr.add_argument("--dry-run", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("task", nargs="?")
    c.add_argument("--run-checks", action="store_true")
    mc = sub.add_parser("merge-check")
    mc.add_argument("task", nargs="?")
    m = sub.add_parser("merge")
    m.add_argument("task")
    m.add_argument("--accept-failing", metavar="REASON")
    cl = sub.add_parser("close")
    cl.add_argument("task")
    cl.add_argument("--force", action="store_true")
    b = sub.add_parser("bundle")
    b.add_argument("task")
    b.add_argument("--out")
    sub.add_parser("status")
    sub.add_parser("models")
    sv = sub.add_parser("serve")
    sv.add_argument("--dry-run", action="store_true")
    sub.add_parser("guard")
    args = p.parse_args(argv)
    handlers = {"start": cmd_start, "agent": cmd_agent, "prepare": cmd_prepare, "check": cmd_check, "merge-check": cmd_merge_check,
                "merge": cmd_merge, "close": cmd_close,
                "bundle": cmd_bundle, "status": cmd_status, "models": cmd_models, "serve": cmd_serve, "guard": cmd_guard}
    try:
        return handlers[args.cmd](args)
    except SideworkError as e:
        print(f"sidework: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
