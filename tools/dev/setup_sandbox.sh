#!/bin/sh
# Recreate the verification environment on Debian/Ubuntu, the way Claude's sandbox needed it.
# Everything is optional: tests that need a missing tool SKIP with a message instead of failing.
# Nothing here is needed on the maintainer's machine, where `nix develop` provides it all.
#
#   tools/dev/setup_sandbox.sh            installs, then prints the environment to export
#   RUTILE_SANDBOX=/path tools/dev/setup_sandbox.sh      where downloads go (default /tmp/rutile-sandbox)
#
# Note: this shell has no brace expansion; mkdir lists every directory explicitly.
set -u
WORK="${RUTILE_SANDBOX:-/tmp/rutile-sandbox}"
mkdir -p "$WORK/bin" "$WORK/fonts/truetype" "$WORK/opencode"
step() { printf '\n== %s\n' "$1"; }
try() { "$@" || echo "   (skipped: $*)"; }
apt_quiet() { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1; }

step "Qt 6.4 tools: qmltestrunner, qmllint, QML modules (Ubuntu 24.04 packages)"
try apt_quiet qt6-declarative-dev-tools qt6-declarative-dev qt6-base-dev qml6-module-qtquick qml6-module-qttest \
    qml6-module-qtqml-workerscript qml6-module-qtquick-window qml6-module-qtquick-templates qml6-module-qtquick-layouts

step "Xvfb + Mesa software OpenGL (renders through the real scene graph, headless)"
try apt_quiet xvfb libgl1-mesa-dri libegl1 libglx-mesa0 libxcb-cursor0 libxkbcommon-x11-0 libxcb-icccm4 \
    libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-shape0 libxcb-xkb1 libfontconfig1 libdbus-1-3

step "matugen 4.2.0 (release binary)"
if [ ! -x "$WORK/bin/matugen" ]; then
  try sh -c "curl -sL -m 120 -o '$WORK/matugen.tgz' https://github.com/InioX/matugen/releases/download/v4.2.0/matugen-4.2.0-x86_64.tar.gz && tar xzf '$WORK/matugen.tgz' -C '$WORK/bin' matugen"
fi

step "Fonts: Google Sans Flex 4.007 and Material Symbols Rounded (pinned commit)"
if [ ! -f "$WORK/fonts/truetype/GoogleSansFlex[GRAD,ROND,opsz,slnt,wdth,wght].ttf" ]; then
  try sh -c "curl -sL -m 120 -o '$WORK/gsf.zip' https://github.com/googlefonts/googlesans-flex/releases/download/v4.007/GoogleSansFlex-v4.007.zip && unzip -oq '$WORK/gsf.zip' -d '$WORK/fonts/truetype'"
fi
if [ ! -f "$WORK/fonts/truetype/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf" ]; then
  try sh -c "curl -sL -m 180 -o '$WORK/fonts/truetype/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf' 'https://raw.githubusercontent.com/google/material-design-icons/bd8cb85bd4bad964fe6918f79665bb40c3a8efef/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf'"
fi

step "Python: materialyoucolor (palette cross-check), PySide6 (modern Qt, optional)"
try pip install -q --break-system-packages materialyoucolor
try pip install -q --break-system-packages PySide6-Essentials PySide6-Addons

step "opencode 1.x (real binary, for the config checks)"
if [ ! -x "$WORK/opencode/node_modules/.bin/opencode" ]; then
  try sh -c "cd '$WORK/opencode' && npm install --silent opencode-ai"
fi

step "nix (evaluation only; see tools/dev/eval_flake.sh)"
try apt_quiet nix-bin

cat <<OUT

Done. Export these before running the checks:

  export PATH="\$PATH:/usr/lib/qt6/bin"
  export RUTILE_MATUGEN="$WORK/bin/matugen"
  export RUTILE_FONT_DIRS="$WORK/fonts"
  export RUTILE_OPENCODE="$WORK/opencode/node_modules/.bin/opencode"

then:  make check
       python3 tools/dev/pyside_qml.py suite                  # same QML tests on a modern Qt
       xvfb-run -a -s "-screen 0 1280x800x24" env QT_QPA_PLATFORM=xcb QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 \\
         python3 tools/dev/pyside_qml.py file tests/qml_gpu/tst_glyphs.qml --gl
OUT
