# Every commit must pass `make check`.
PY ?= python3

.PHONY: check tokens tokens-check generate generate-check test lint qmllint flake-check

check: tokens-check generate-check test lint qmllint

tokens:
	$(PY) tools/gen_tokens.py

tokens-check:
	$(PY) tools/gen_tokens.py --check

# Regenerate the QML token singletons after changing tokens or roles.
generate:
	$(PY) tools/gen_qml.py

generate-check:
	$(PY) tools/gen_qml.py --check

test:
	$(PY) -m unittest discover -s tests -v

lint:
	$(PY) tools/lint_hardcoded.py

# Lints the QML that does not need Quickshell; skips (loudly) if Qt tools are missing.
qmllint:
	$(PY) tools/qtws.py lint

# Needs nix with flakes and network on first run; not part of `make check`.
flake-check:
	nix flake check --no-build
