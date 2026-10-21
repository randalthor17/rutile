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


def derived_name(tier_name, models):
    return f"{models['derived_prefix']}{tier_name}:{models['context'] // 1024}k"


def modelfile_text(tag, models, temperature):
    return f"FROM {tag}\nPARAMETER num_ctx {models['context']}\nPARAMETER temperature {temperature}\n"


def opencode_config(cfg, models, model_name, temperature, allowed, instructions):
    """The inline config handed to opencode through OPENCODE_CONFIG_CONTENT (opencode 1.x schema).

    It is passed inline because that outranks a project opencode.json inside the worktree, which
    the agent could create or edit. Rules in a permission map are evaluated last-match-wins.
    """
    host = host_of(models)
    base = host if host.startswith("http") else f"http://{host}"
    edit = {"*": "deny"}
    for pat in allowed:
        edit[glob_for_opencode(pat)] = "allow"
    # the guard and the config are never editable, whatever the allowlist says
    for pat in cfg["always_forbidden"]:
        edit[glob_for_opencode(pat)] = "deny"
    bash = {"*": "allow"}
    bash.update({pat: "deny" for pat in BASH_DENY})
    return {
        "$schema": "https://opencode.ai/config.json",
        "model": f"ollama/{model_name}",
        "enabled_providers": ["ollama"],      # never fall back to a cloud provider
        "autoupdate": False,
        "share": "disabled",
        "snapshot": False,                    # the branch's own commits are the history
        "instructions": instructions,
        "provider": {
            "ollama": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "Ollama (local)",
                "options": {"baseURL": base + "/v1", "apiKey": "ollama"},
                "models": {
                    model_name: {
                        "name": model_name,
                        # without this opencode silently sends no tools and the agent can do nothing
                        "tool_call": True,
                        "limit": {"context": models["context"], "output": models["output_tokens"]},
                        "options": {"temperature": temperature},
                    }
                },
            }
        },
        "permission": {
            "edit": edit,
            "bash": bash,
            "external_directory": {"*": "deny"},   # nothing outside the worktree
            "webfetch": "deny",
            "websearch": "deny",
            "doom_loop": "deny",                   # stop a model repeating the same failing call
        },
        "compaction": {"auto": True, "prune": True},
    }


def agent_env(cfg, models, base_env, config):
    env = dict(base_env)
    ident = cfg["identity"]
    for who in ("AUTHOR", "COMMITTER"):
        env[f"GIT_{who}_NAME"] = ident["name"]
        env[f"GIT_{who}_EMAIL"] = ident["email"]
    env["OPENCODE_CONFIG_CONTENT"] = json.dumps(config)
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
    m = re.match(r"(\d+)\.", out)
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
    if args.unattended or args.prompt:
        cmd = ["opencode", "run", "--model", f"ollama/{name}", "--title", args.task]
        if args.unattended:
            cmd.append("--auto")
        cmd.append(prompt)
    else:
        cmd = ["opencode"]
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
    if found[0] != 1:
        raise SideworkError(f"opencode {found[1]} found, but the generated config follows the 1.x schema "
                            "(2.x renamed the model and provider fields). Use a 1.x opencode, or update tools/sidework.py")
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
                "bundle": cmd_bundle, "status": cmd_status, "models": cmd_models, "serve": cmd_serve, "guard": cmd_guard}
    try:
        return handlers[args.cmd](args)
    except SideworkError as e:
        print(f"sidework: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
