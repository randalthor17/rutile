#!/usr/bin/env python3
"""Run a local model on side tasks without it ever clashing with the main line of work.

The idea is to make merge conflicts impossible, not just unlikely: the local model works on a
`local/<task>` branch in its own git worktree, and may only change paths listed in
tools/ownership.json (`local_owned`). A pre-commit hook enforces that at commit time, so even an
agent that wanders cannot commit outside its area. Claude's sessions leave those paths alone.

    sidework.py start TASK [--path GLOB ...] [--dir DIR] [--base REF]
                                   create branch local/TASK in a new worktree, install the guard
    sidework.py agent TASK [--tier T | --model TAG] [--dry-run]
                                   run aider on that worktree with a local Ollama model
    sidework.py check [TASK] [--run-checks]
                                   verify a branch only touches allowed paths (and `make check`)
    sidework.py merge-check [TASK] dry-run the merge into main; fails on any conflict
    sidework.py bundle TASK [--out FILE]
                                   a git bundle of the branch's commits, to hand over
    sidework.py status             list local/* branches and whether each is clean to merge
    sidework.py models             the model tiers and which are pulled in Ollama
    sidework.py serve [--dry-run]  start `ollama serve` with the settings in tools/local_models.json
    sidework.py guard              (used by the pre-commit hook)
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
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
    if not bad:
        return 0
    print(f"sidework: commit rejected on {branch}: it touches paths this branch does not own", file=sys.stderr)
    for path, why in bad:
        print(f"  {path}  ({why})", file=sys.stderr)
    print("Allowed: " + ", ".join(allowed), file=sys.stderr)
    print("Unstage those files (git restore --staged <path>) and commit only your own area.", file=sys.stderr)
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
    if args.run_checks:
        wt = worktree_of(branch)
        if wt is None:
            raise SideworkError(f"{branch} has no worktree to run `make check` in")
        print("running make check ...")
        code = subprocess.run(["make", "check"], cwd=wt).returncode
        if code != 0:
            print("make check failed", file=sys.stderr)
            return 1
    print("ok: only allowed paths changed")
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
        print(f"{br:30s} {ahead:>3} commit(s)  paths:{'OK' if not bad else 'VIOLATED'}  "
              f"merge:{'clean' if clean else 'CONFLICT'}  {wt or '(no worktree)'}")
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
    print(f"GPU memory budget {m['vram_gb']} GB, context {m['context']}, default tier {m['default_tier']}\n")
    for name, t in m["tiers"].items():
        ok, need = fits(t, m)
        have = "pulled" if pulled and t["tag"] in pulled else "not pulled"
        print(f"{name:8s} {t['tag']:22s} ~{need:4.1f} GB needed  {'fits' if ok else 'SPILLS TO CPU':13s} {have}")
        print(f"         {t['note']}")
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


def aider_command(task_file, tag, settings_file="aider.model.settings.yml"):
    cmd = ["aider", "--model", f"ollama_chat/{tag}",
           "--read", "docs/sidework/CONVENTIONS.md"]
    if task_file:
        cmd += ["--read", task_file]
    # aider skips git hooks by default (it commits with --no-verify); --git-commit-verify makes it honor the guard
    cmd += ["--git-commit-verify", "--model-settings-file", settings_file, "--analytics-disable",
            "--no-check-update", "--no-show-release-notes"]
    return cmd


def agent_env(cfg, models, base_env):
    env = dict(base_env)
    host = host_of(models)
    env["OLLAMA_API_BASE"] = host if host.startswith("http") else f"http://{host}"
    ident = cfg["identity"]
    for who in ("AUTHOR", "COMMITTER"):
        env[f"GIT_{who}_NAME"] = ident["name"]
        env[f"GIT_{who}_EMAIL"] = ident["email"]
    env.update(models.get("env", {}))
    return env


def settings_yaml(tag, context):
    return f"- name: ollama_chat/{tag}\n  extra_params:\n    num_ctx: {context}\n"


def cmd_agent(args):
    cfg, models = load_config(), load_models()
    branch = branch_name(args.task, cfg)
    wt = worktree_of(branch)
    if wt is None:
        raise SideworkError(f"no worktree for {branch}; run `sidework.py start {args.task}` first")
    tier_name = args.tier or models["default_tier"]
    if args.model:
        tag = args.model
    else:
        if tier_name not in models["tiers"]:
            raise SideworkError(f"unknown tier {tier_name!r}; choose from {', '.join(models['tiers'])}")
        tag = models["tiers"][tier_name]["tag"]
    task_file = f"docs/sidework/tasks/{args.task}.md"
    task_file = task_file if (wt / task_file).exists() else None
    settings = "aider.model.settings.yml"
    cmd = aider_command(task_file, tag, settings)
    env = agent_env(cfg, models, os.environ)
    if args.dry_run:
        print("cwd      ", wt)
        print("command  ", " ".join(cmd))
        print("settings ", settings_yaml(tag, models["context"]).strip().replace("\n", " | "))
        print("identity ", f"{env['GIT_AUTHOR_NAME']} <{env['GIT_AUTHOR_EMAIL']}>")
        print("env      ", ", ".join(f"{k}={env[k]}" for k in sorted(models.get("env", {}))))
        return 0
    pulled = ollama_tags(host_of(models))
    if pulled is None:
        raise SideworkError(
            f"Ollama is not reachable at {host_of(models)}. Start it (`ollama serve`, or enable the NixOS "
            "service from docs/sidework.md) and try again.")
    if tag not in pulled:
        raise SideworkError(f"{tag} is not pulled yet: run `ollama pull {tag}` first")
    (wt / settings).write_text(settings_yaml(tag, models["context"]))
    exclude = common_dir(wt) / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    existing = exclude.read_text() if exclude.exists() else ""
    for pat in (settings, ".aider*"):
        if pat not in existing.splitlines():
            existing += ("" if existing.endswith("\n") or not existing else "\n") + pat + "\n"
    exclude.write_text(existing)
    os.chdir(wt)
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
    a.add_argument("--dry-run", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("task", nargs="?")
    c.add_argument("--run-checks", action="store_true")
    mc = sub.add_parser("merge-check")
    mc.add_argument("task", nargs="?")
    b = sub.add_parser("bundle")
    b.add_argument("task")
    b.add_argument("--out")
    sub.add_parser("status")
    sub.add_parser("models")
    sv = sub.add_parser("serve")
    sv.add_argument("--dry-run", action="store_true")
    sub.add_parser("guard")
    args = p.parse_args(argv)
    handlers = {"start": cmd_start, "agent": cmd_agent, "check": cmd_check, "merge-check": cmd_merge_check,
                "bundle": cmd_bundle, "status": cmd_status, "models": cmd_models, "serve": cmd_serve, "guard": cmd_guard}
    try:
        return handlers[args.cmd](args)
    except SideworkError as e:
        print(f"sidework: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
