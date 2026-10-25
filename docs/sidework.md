# Side work with a local model

Claude's sessions hit usage limits. This sets up a local model on the Radeon RX 9060 XT (16 GB) that keeps
working in the meantime on **bounded tasks in paths Claude does not touch**, so merging its work can never
conflict. The agent is [opencode](https://opencode.ai) talking to Ollama.

## How conflicts are made impossible

1. **Disjoint ownership.** `tools/ownership.json` lists `local_owned` paths (today `widgets/**` and
   `docs/llm/**`). Claude's sessions do not edit those while a local branch is open.
2. **A worktree and a branch per task.** `sidework.py start TASK` creates `local/TASK` in its own directory,
   so the local model never shares a working tree with anything else.
3. **Enforced at commit time.** A pre-commit hook rejects any commit on a `local/*` branch that touches a path
   outside the task's allowlist. The guard itself, the config, the flake and `Makefile` are *always
   forbidden*, even if a task is granted a broader area.
4. **The rules cannot be edited from inside the worktree.** The hook is installed from the main checkout
   (absolute `core.hooksPath`) and runs the main checkout's `sidework.py` with the main checkout's
   `ownership.json`. The per-task allowlist lives in `.git/`, outside the worktree. Tests simulate both
   attacks (weakening the rules, replacing the guard) and confirm they succeed against the old design.
5. **Backstops before anything is merged.** `sidework.py check` re-verifies the whole branch (it catches commits
   made with `--no-verify`), `--run-checks` runs `make check` in the worktree, and `merge-check` does a dry-run
   merge that touches nothing.
6. **A first layer inside the agent.** The launcher hands opencode a permission config that denies edits
   outside the allowlist, `git push`, `git config`, `--no-verify`, network commands and anything outside the
   worktree, removes the `execute`, `webfetch` and `websearch` tools, and blocks every provider but Ollama.
   This is **not a sandbox**: the agent has a shell tool and can write files by other means (`echo > file`
   works, and the trial model did exactly that to `flake.nix`). It stops accidental straying; the commit
   guard and `check` stop anything out of scope from reaching history.

The config is passed inline through `OPENCODE_CONFIG_CONTENT`. opencode 2.x merges it after any project
`opencode.json`, and its permission rules are an ordered list where the last match wins. Every action we
restrict starts with a catch-all rule of ours, so a project file cannot widen anything: verified with the real
opencode 2.1.1 driven through a scripted model, with a hostile `opencode.json` that allows everything in place
(it was loaded, and every rule still held). `execute` is removed because it runs JavaScript that can call
`fetch` and opencode's own worktree tools, which ask for no permission; a model used it to create a stray
worktree under `~/.local/share/opencode`.

Three 2.x behaviours the launcher works around, all found by running the real binary:

- opencode normally attaches to a **background service** (a server started earlier, with its own environment),
  which would never see `OPENCODE_CONFIG_CONTENT`. The launcher always passes `--standalone`.
- opencode takes its working directory from **`$PWD`** when set, not from the directory it was started in. The
  launcher sets `PWD` to the worktree; with the inherited value the agent would work in the main checkout.
- `opencode run` reads a piped **stdin** as part of the prompt and waits for it to end. Started from anything
  that leaves stdin open (cron, systemd, an IDE, Claude Code), a headless run hangs before its first request. The
  launcher gives headless runs `/dev/null` as stdin.

`OPENCODE_DISABLE_PROJECT_CONFIG` is deliberately not used: in 2.1.1 it also drops `AGENTS.md` and our own
`instructions`, so the model would lose its conventions.

## Setup

**Option A: Ollama as a system service (recommended on NixOS).** In your system flake:

```nix
inputs.rutile.url = "path:/home/rand/Downloads/rutile";      # wherever the repo lives
# ...
modules = [ rutile.nixosModules.local-ai ];
```

That enables `services.ollama` with the ROCm build and the settings from `tools/local_models.json` (flash
attention, `q8_0` KV cache, 32K context). If ROCm misbehaves on the card, add
`services.ollama.package = pkgs.ollama-vulkan;`.

**Option B: only in a shell.** `nix develop .#local-ai`, then `python3 tools/sidework.py serve`. This shell is
x86_64-only and separate from the everyday one because the ROCm build is a multi-gigabyte closure. It
provides `ollama-rocm`, `opencode` (2.x), `radeontop` and `claude-code` (the one unfree package the flake
allows, by name).

Then pull a model, bake in the context, and check it runs on the GPU:

```
ollama pull qwen3:14b
python3 tools/sidework.py prepare        # creates rutile-main:32k (qwen3:14b with a 32K context)
python3 tools/sidework.py models         # tiers, whether they fit 16 GB, which are pulled and prepared
ollama ps                                # while a model is loaded: PROCESSOR should say 100% GPU
radeontop                                # GPU load
```

The RX 9060 XT is RDNA4 (gfx1200), which needs ROCm 7.x; it should not need `HSA_OVERRIDE_GFX_VERSION`. If
`ollama ps` shows CPU, try the Vulkan build first.

## Daily flow

```
python3 tools/sidework.py start widget-schema          # branch local/widget-schema in ../rutile-local-widget-schema
python3 tools/sidework.py agent widget-schema          # interactive opencode, brief and conventions preloaded
python3 tools/sidework.py agent widget-schema --unattended   # or: headless run on the default task prompt
python3 tools/widget_check.py                          # in the worktree: the widget tasks' acceptance check
python3 tools/sidework.py check widget-schema --run-checks   # also lists uncommitted leftovers in the worktree
python3 tools/sidework.py merge-check widget-schema
git merge --no-ff local/widget-schema                  # or: sidework.py bundle widget-schema
python3 tools/sidework.py status                       # all local branches at a glance
```

`--unattended` runs `opencode run --auto`, which approves everything that is not explicitly denied: use it
for the well-specified briefs, then read the diff. `--prompt TEXT` runs one headless prompt without `--auto`.
Local commits are authored as `local-model <local-model@localhost>`, so history shows who did what. Tell
Claude which task branches you merged; at the start of a new Claude session, upload the current bundle so
Claude works from the merged state.

## Why these models

An agent needs two things a chat model does not: reliable **tool calling** and a **long context**.

- Ollama defaults to a 4096-token context, which an agent's system prompt and tool list alone can overflow, so
  tool calls get cut off. The OpenAI-compatible endpoint ignores a per-request context, hence `sidework.py
  prepare`, which bakes `num_ctx` into a derived model (`rutile-<tier>:32k`). The server also gets
  `OLLAMA_CONTEXT_LENGTH`.
- opencode 1.x needed `"tool_call": true` on the model or it silently sent no tools. In 2.x the field is
  `capabilities.tools`; 2.1.1 was observed to send tools even without it, but the launcher still declares it.
- A custom provider needs `"package": "@ai-sdk/openai-compatible"` in 2.x, or every request fails with
  `Unsupported package`.
- `qwen2.5-coder` was dropped as the default: it is reported to hang in opencode's tool loop. The tiers are
  the Qwen3 family: `qwen3:14b` (default, about 9 GB), `qwen3:8b` (fast), and `qwen3-coder:30b`, which is built
  for agentic coding but does not fit in 16 GB, so part runs on the CPU. Measure its speed before relying on it.
- Expect roughly 30 tokens per second from a 14B at 4-bit (the card's memory bandwidth), and a thinking
  mode that spends tokens before answering. Local models around this size are noticeably less dependable than
  a cloud model at long tool loops: keep tasks small and the acceptance checks explicit.

Tags and sizes come from third-party summaries of the Ollama library: confirm with `ollama pull`.

## What to give the local model, and what not to

| Good fit (bounded, checkable, low coupling) | Keep with Claude |
|---|---|
| JSON Schema, template files, data (`widgets/**`) | anything in `shell/`, `tools/`, `tokens/`, `theme/`, `nix/` |
| reference docs for LLMs (`docs/llm/**`) | build, flake, CI, hooks, ownership rules |
| drafting prose from facts already in the repo | rendering, fonts, motion, anything needing a debugger |
| more examples, fixtures, variants of existing files | design decisions and architecture |

Every task ends with a gate: `check`, `merge-check`, then Claude reviews the diff in the next session and adds
tests for what the model produced.

## Troubleshooting

- **The agent says nothing and changes nothing:** the model does not support tools, or the config did not reach
  opencode. Run `sidework.py agent TASK --dry-run` and check the config; try another tier.
- **`Unsupported package for ollama/...`:** the provider block lacks `package` (an old or hand-made config).
- **Tool calls look truncated or the agent forgets the task:** the context is too small. Run `sidework.py
  models` and check the tier shows as prepared; `ollama ps` shows the loaded context.
- **`opencode 1.x found`:** the generated config follows the 2.x schema (1.x used `provider`, `permission` and
  `tool_call`). Use the opencode from `nix develop .#local-ai`.
- **The agent keeps fighting a missing tool** (installing packages, editing the flake): its brief must name a
  check that runs with what is in the repo. For the widget tasks that is `tools/widget_check.py` (stdlib only).
- **Slow or CPU-bound:** `ollama ps`; try `qwen3:8b`, the Vulkan build, or a smaller context.

## What is verified, and what is not

Tested here with real git repositories: the guard and its two attacks, per-task allowlists, rename and delete
handling, `check` (including the leftover report), `merge-check` (clean and conflicting), `bundle`, `status`. The
launcher is tested through fake `opencode` and `ollama` executables (working directory, `PWD`, arguments,
environment, identity, every preflight message). Against the **real opencode 2.1.1**, with a private HOME and a
scripted OpenAI-compatible model standing in for Ollama: opencode keeps every key of the generated config (it
drops unknown keys silently, and a test proves that check can fail), requests carry our model, temperature,
tools and instructions, and 22 scripted tool calls (edits, shell commands, an outside path, `execute`,
`webfetch`) are allowed or refused as intended with a hostile project config present. Evaluated against real
nixpkgs: both shells, and the module inside a real `nixosSystem`.

**Not verified:** the interactive TUI (only `opencode run` was driven), that ROCm runs on your card, Ollama
end to end with these models, token speeds, and how good the models are at these tasks. The first trial
(`widget-schema`, October 2026) ran on `rutile-main:32k` before these fixes; see `docs/LESSONS.md`.
