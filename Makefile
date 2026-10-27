# Every commit must pass `make check`.
PY ?= python3

.PHONY: gallery render check-gpu check tokens tokens-check generate generate-check test lint qmllint flake-check native

check: tokens-check generate-check native test lint qmllint

# The one compiled program (D54): the Firefox colors' host. Strict warnings, hardened; tests build their own
# copy with AddressSanitizer and UBSan (tests/test_pywalfox_host.py).
CC ?= cc
NATIVE_FLAGS = -std=c11 -O2 -g -Wall -Wextra -Werror -Wshadow -Wconversion -Wformat=2 -Wstrict-prototypes \
	-Wmissing-prototypes -Wvla -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now
native: build/rutile-pywalfox-host

build/rutile-pywalfox-host: native/pywalfox-host.c
	@mkdir -p build
	$(CC) $(NATIVE_FLAGS) -o $@ $<

tokens:
	$(PY) tools/gen_tokens.py
	$(PY) tools/gen_components.py

tokens-check:
	$(PY) tools/gen_tokens.py --check
	$(PY) tools/gen_components.py --check

# Regenerate the QML token singletons after changing tokens or roles.
generate:
	$(PY) tools/gen_qml.py
	$(PY) tools/gen_settings.py

generate-check:
	$(PY) tools/gen_qml.py --check
	$(PY) tools/gen_settings.py --check

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

# Open the component gallery in Quickshell (needs a graphical session).
gallery:
	quickshell -p shell/gallery.qml

# Offscreen PNG slices of the gallery in ./render (needs the Qt tools).
render:
	$(PY) tools/qtws.py render --out render --mode dark
	$(PY) tools/qtws.py render --out render --mode light

# GPU-path rendering checks (need a graphical session; not part of `make check`).
check-gpu:
	$(PY) tools/qtws.py test-gpu
