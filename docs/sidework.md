# Side work with a local model

Claude's sessions hit usage limits. This sets up a local model on the Radeon RX 9060 XT (16 GB) that
keeps working in the meantime on **bounded tasks in paths Claude does not touch**, so merging its work
can never conflict.

## How conflicts are made impossible

1. **Disjoint ownership.** `tools/ownership.json` lists `local_owned` paths (today `widgets/**` and
   `docs/llm/**`). Claude's sessions do not edit those while a local branch is open.
2. **A worktree and a branch per task.** `sidework.py start TASK` creates `local/TASK` in its own
   directory, so the local model never shares a working tree with anything else.
3. **Enforced at commit time.** A pre-commit hook rejects any commit on a `local/*` branch that touches a
   path outside the task's allowlist. The guard itself, the config, the flake and `Makefile` are
   *always forbidden*, even if a task is granted a broader area.
4. **The rules cannot be edited from inside the worktree.** The hook is installed from the main
   checkout (absolute `core.hooksPath`) and runs the main checkout's `sidework.py` with the main
   checkout's `ownership.json`. The per-task allowlist lives in `.git/`, outside the worktree.
   Tests simulate both attacks (weakening the rules, replacing the guard) against the old design and
   confirm they fail there.
5. **Backstops before anything is merged.** `sidework.py check` re-verifies the whole branch (it catches
   commits made with `--no-verify`), `--run-checks` runs `make check` in the worktree, and
   `merge-check` does a dry-run merge that touches nothing.

aider commits with `--no-verify` by default (checked in its source), so the launcher passes
`--git-commit-verify` to make it honor the guard.

## Setup

**Option A: Ollama as a system service (recommended on NixOS).** In your system flake:

```nix
inputs.rutile.url = "path:/home/rand/Downloads/rutile";      # wherever the repo lives
# ...
modules = [ rutile.nixosModules.local-ai ];
```

That enables `services.ollama` with the ROCm build and the settings from `tools/local_models.json`
(flash attention, `q8_0` KV cache, 16K context). If ROCm misbehaves on the card, add
`services.ollama.package = pkgs.ollama-vulkan;`.

**Option B: only in a shell.** `nix develop .#local-ai`, then `python3 tools/sidework.py serve`.
This shell is x86_64-only and separate from the everyday one because the ROCm build is a
multi-gigabyte closure.

Then pull a model and check it runs on the GPU:

```
ollama pull qwen2.5-coder:14b
python3 tools/sidework.py models      # tiers, whether they fit 16 GB, which are pulled
ollama ps                             # while a model is loaded: PROCESSOR should say 100% GPU
radeontop                             # GPU load
```

The RX 9060 XT is RDNA4 (gfx1200), which needs ROCm 7.x; it should not need
`HSA_OVERRIDE_GFX_VERSION`. If `ollama ps` shows CPU, try the Vulkan build first.

## Daily flow

```
python3 tools/sidework.py start widget-schema        # branch local/widget-schema in ../rutile-local-widget-schema
python3 tools/sidework.py agent widget-schema        # aider + the local model, brief and conventions preloaded
python3 tools/sidework.py check widget-schema --run-checks
python3 tools/sidework.py merge-check widget-schema
git merge --no-ff local/widget-schema                # or: sidework.py bundle widget-schema
python3 tools/sidework.py status                     # all local branches at a glance
```

Local commits are authored as `local-model <local-model@localhost>`, so history shows who did what.
Tell Claude which task branches you merged; at the start of a new Claude session, upload the current
`rutile-*.bundle` so Claude works from the merged state.

## What to give the local model, and what not to

| Good fit (bounded, checkable, low coupling) | Keep with Claude |
|---|---|
| JSON Schema, template files, data (`widgets/**`) | anything in `shell/`, `tools/`, `tokens/`, `theme/`, `nix/` |
| reference docs for LLMs (`docs/llm/**`) | build, flake, CI, hooks, ownership rules |
| drafting prose from facts already in the repo | rendering, fonts, motion, anything needing a debugger |
| more examples, fixtures, variants of existing files | design decisions and architecture |

Every task ends with a gate: `check`, `merge-check`, then Claude reviews the diff in the next session and
adds tests for what the model produced. A 14B model is much weaker than Claude at multi-file reasoning;
it is for volume work, not judgment.

## Models (16 GB, ~320 GB/s)

`tools/local_models.json` holds the tiers. The default is `qwen2.5-coder:14b` (about 9 GB, so weights
plus a 16K context fit). `qwen3:14b` is the general/thinking alternative; `qwen2.5-coder:7b` is the
fast tier; `qwen3-coder:30b` does not fit and runs partly on the CPU, so measure its speed before
using it. Expect roughly 30 tokens per second from a 14B at 4-bit, which is the card's memory bandwidth
talking. Tags and sizes come from third-party summaries of the Ollama library: confirm with
`ollama pull`.

## What is verified, and what is not

Tested here with real git repositories: the guard and its two attacks, per-task allowlists, rename and
delete handling, `check`, `merge-check` (clean and conflicting), `bundle`, `status`, the agent command
line (flags verified against aider's source), Ollama reachability and model-pulled messages.
Evaluated against real nixpkgs: both shells, the module inside a real `nixosSystem` (it selects
`ollama-rocm`, and the environment reaches the systemd unit).

**Not verified, because it needs your hardware:** that ROCm actually runs on your card, that
Ollama and aider run end to end, token speeds, and how good the models are at these tasks.
