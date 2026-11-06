# Rutile Shell as a package (plan 6.1): the QML shell, the theme templates it renders from, the compiled Firefox
# host (D54), and `rutile-shell` (bin/rutile-shell), which runs it under Quickshell with everything it calls on PATH
# and its fonts visible to Qt, Papirus-Dark for its icons (after the user's own folders; D62), and calls the running one (`rutile-shell lock lock`; `rutile-shell --help` lists all).
# GPU widgets name cards from libdrm's amdgpu.ids (libdrm is in Qt's closure already) and hwdata's pci.ids (D87).
# The calendar reads evolution-data-server through rutile-calendar (native/calendar.c, built on libecal) and opens
# GNOME Calendar and GNOME Online Accounts' window (D95); the system runs the data server and the accounts daemon
# (docs/install.md).
{
  lib,
  stdenv,
  makeWrapper,
  writeText,
  quickshell,
  matugen,
  brightnessctl,
  ddcutil,
  curl,
  wlsunset,
  pipewire,
  dbus,
  systemd,
  procps,
  coreutils,
  gnused,
  dconf,
  glib,
  bash,
  material-symbols,
  google-sans-flex,
  papirus-icon-theme,
  libdrm,
  hwdata,
  unicode-emoji,
  pkg-config,
  evolution-data-server,
  gnome-calendar,
  gnome-online-accounts-gtk,
  qt6Packages,
  fcitx5-m17n,
  cliphist,
  wl-clipboard,
  grim,
  slurp,
  wf-recorder,
}:
let
  # The system's fontconfig first (every other font keeps working), then the two fonts the shell is drawn with.
  fontsConf = writeText "rutile-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
      <dir>${google-sans-flex}/share/fonts</dir>
      <dir>${material-symbols}/share/fonts</dir>
    </fontconfig>
  '';
  # What the shell runs (Process, execDetached): matugen (palette, other apps' colors), brightnessctl (backlight),
  # ddcutil (monitors' brightness, D113), cliphist and wl-clipboard (clipboard history, D119), grim, slurp
  # and wf-recorder (screenshots without niri, recording, D120), pw-play (notification sounds), dbus-monitor (logind's Lock), systemctl/systemd-inhibit/busctl (power, lock
  # before sleep, LockedHint), pkill (apps' reload), sh, coreutils and sed (file jobs; the folder icons, D64), dconf
# and gsettings (GTK's dark or light, D65), wlsunset (Night light, D91), GNOME Calendar and the
# accounts window (D95). niri itself comes from the system.
  # Typing in other languages (D118): fcitx5 with m17n's input methods and its settings tool. The shell starts it
  # only when no fcitx5 runs (a system's own, with the user's addons, wins), so it is named, not put on PATH.
  fcitx5 = qt6Packages.fcitx5-with-addons.override { addons = [ fcitx5-m17n ]; };
  runtime = [ matugen curl brightnessctl ddcutil cliphist wl-clipboard grim slurp wf-recorder wlsunset pipewire dbus systemd procps coreutils gnused dconf glib bash
              gnome-calendar gnome-online-accounts-gtk ];
in
stdenv.mkDerivation {
  pname = "rutile-shell";
  version = "0.11.0";                     # the latest release in CHANGELOG.md (a test checks)

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Makefile
      ../bin
      ../native
      ../shell
      ../share
      ../widgets/examples
      ../widgets/templates
      ../theme/apps
      ../theme/templates
      ../theme/roles.json
      ../theme/fixtures/palette-134aae-tonal-spot-dark.json # the greeter's colors by default (D97)
      ../theme/wallpapers/rutile-default.jpg # the wallpaper when none is set, and the greeter's (D98)
    ];
  };

  nativeBuildInputs = [ makeWrapper pkg-config ];
  buildInputs = [ evolution-data-server ];

  buildPhase = ''
    runHook preBuild
    make native CC=$CC
    runHook postBuild
  '';

  # The shell finds ../theme and ../build beside its own folder.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/rutile/build
    cp -r shell theme $out/share/rutile/
    mkdir -p $out/share/rutile/widgets && cp -r widgets/examples widgets/templates $out/share/rutile/widgets/
    install -Dm755 build/rutile-pywalfox-host $out/share/rutile/build/rutile-pywalfox-host
    install -Dm755 build/rutile-calendar $out/share/rutile/build/rutile-calendar
    install -Dm755 bin/rutile-shell $out/share/rutile/bin/rutile-shell
    # the Settings and Widgets apps in app launchers, run by this package's own CLI
    for app in settings widgets; do
      install -Dm644 share/applications/rutile-$app.desktop $out/share/applications/rutile-$app.desktop
      substituteInPlace $out/share/applications/rutile-$app.desktop \
        --replace-fail "Exec=rutile-shell " "Exec=$out/bin/rutile-shell "
    done
    makeWrapper $out/share/rutile/bin/rutile-shell $out/bin/rutile-shell \
      --set RUTILE_SHELL_QML $out/share/rutile/shell/shell.qml \
      --set RUTILE_CLI $out/bin/rutile-shell \
      --prefix PATH : ${lib.makeBinPath ([ quickshell ] ++ runtime)} \
      --set FONTCONFIG_FILE ${fontsConf} \
      --suffix XDG_DATA_DIRS : ${papirus-icon-theme}/share \
      --set RUTILE_AMDGPU_IDS ${libdrm}/share/libdrm/amdgpu.ids \
      --set RUTILE_PCI_IDS ${hwdata}/share/hwdata/pci.ids \
      --set-default RUTILE_FCITX5 ${fcitx5}/bin/fcitx5 \
      --set-default RUTILE_FCITX5_CONFIGTOOL ${fcitx5}/bin/fcitx5-configtool \
      --set-default RUTILE_EMOJI_DATA ${unicode-emoji}/share/unicode/emoji/emoji-test.txt
    runHook postInstall
  '';

  meta = {
    description = "A Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";
    mainProgram = "rutile-shell";
    platforms = lib.platforms.linux;
  };
}
