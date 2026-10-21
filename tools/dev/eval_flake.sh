#!/bin/sh
# Evaluate the flake's outputs WITHOUT building them, taking nixpkgs from a codeload tarball.
#
# Normally `make flake-check` is enough. This exists for places where the GitHub API is rate limited
# (a fresh `nix flake lock` fails with HTTP 403 there): git can still read refs and codeload.github.com
# serves tarballs. Evaluation catches wrong attribute names, syntax errors and unsupported platforms;
# it does not prove anything builds or runs.
#
#   tools/dev/eval_flake.sh [NIXPKGS_REV]       default: current nixos-unstable
#
# Set NIX_STORE_ROOT to evaluate into a private store (needed when /nix is not writable).
set -eu
REV="${1:-$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/nixos-unstable | cut -f1)}"
[ -n "$REV" ] || { echo "could not determine a nixpkgs revision" >&2; exit 2; }
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"
if [ -n "${NIX_STORE_ROOT:-}" ]; then NIX="$NIX --store $NIX_STORE_ROOT --option sandbox false"; fi
OV="--override-input nixpkgs tarball+https://codeload.github.com/NixOS/nixpkgs/tar.gz/$REV --no-write-lock-file"
git add -A >/dev/null 2>&1 || true      # flakes only see tracked files
echo "nixpkgs $REV"
status=0
for attr in \
    devShells.x86_64-linux.default \
    devShells.x86_64-linux.local-ai \
    devShells.aarch64-linux.default \
    packages.x86_64-linux.google-sans-flex \
    packages.aarch64-linux.google-sans-flex; do
  # shellcheck disable=SC2086
  if out=$($NIX eval --raw ".#$attr.drvPath" $OV 2>&1); then
    printf '%-44s ok  %s\n' "$attr" "$(basename "$out" .drv | cut -c1-40)"
  else
    printf '%-44s FAILED\n%s\n' "$attr" "$out" >&2
    status=1
  fi
done
exit $status
