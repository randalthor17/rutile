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
   worktree, and disables every cloud provider. This is **not a sandbox**: the agent has a bash tool and can
   write files by other means. It stops accidental straying; the commit guard and `check` stop anything out of
   scope from reaching history.

The config is passed inline through `OPENCODE_CONFIG_CONTENT`, which ranks above a project `opencode.json`
in opencode's precedence, so a file the agent creates in the worktree cannot override the keys we set
(verified against the real opencode: model, providers, sharing, `webfetch`, `external_directory` and
`bash` rules all stayed ours). One caveat, also observed: permission maps are merged key by key and the
last matching rule wins, so a hostile project file that defines extra patterns could widen what is allowed.
That is why the guard is the real boundary.

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
provides `ollama-rocm`, `opencode` (1.x) and `radeontop`.

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
python3 tools/sidework.py check widget-schema --run-checks
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
- The model entry must say `"tool_call": true`, or opencode silently sends no tools and the agent produces no
  output and writes nothing, with no error. The launcher always sets it.
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

- **The agent says nothing and changes nothing:** the model entry lacks `tool_call`, or the model does not
  support tools. Run `sidework.py agent TASK --dry-run` and check the config; try another tier.
- **Tool calls look truncated or the agent forgets the task:** the context is too small. Run `sidework.py
  models` and check the tier shows as prepared; `ollama ps` shows the loaded context.
- **`opencode 2.x found`:** the generated config follows the 1.x schema (2.x renamed the provider and model
  fields). Use the opencode from `nix develop .#local-ai`.
- **Slow or CPU-bound:** `ollama ps`; try `qwen3:8b`, the Vulkan build, or a smaller context.

## What is verified, and what is not

Tested here with real git repositories: the guard and its two attacks, per-task allowlists, rename and delete
handling, `check`, `merge-check` (clean and conflicting), `bundle`, `status`. The launcher is tested through
fake `opencode` and `ollama` executables (working directory, arguments, environment, identity, every
preflight message) and against the **real opencode 1.19** binary: it accepts the generated config, our
settings win over a hostile project `opencode.json`, and its resolved permission rules decide 23 sample
edits, commands and paths as intended. Evaluated against real nixpkgs: both shells, and the module inside a
real `nixosSystem` (it selects `ollama-rocm`, and the environment reaches the systemd unit).

**Not verified, because it needs your hardware:** that ROCm runs on your card, that Ollama and opencode run
end to end with these models, token speeds, tool-calling reliability, and how good the models are at these
tasks. Treat the first task as a trial.
