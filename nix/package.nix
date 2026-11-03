# Rutile Shell as a package (plan 6.1): the QML shell, the theme templates it renders from, the compiled Firefox
# host (D54), and `rutile-shell` (bin/rutile-shell), which runs it under Quickshell with everything it calls on PATH
# and its fonts visible to Qt, Papirus-Dark for its icons (after the user's own folders; D62), and calls the running one (`rutile-shell lock lock`; `rutile-shell --help` lists all).
{
  lib,
  stdenv,
  makeWrapper,
  writeText,
  quickshell,
  matugen,
  brightnessctl,
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
  # pw-play (notification sounds), dbus-monitor (logind's Lock), systemctl/systemd-inhibit/busctl (power, lock
  # before sleep, LockedHint), pkill (apps' reload), sh, coreutils and sed (file jobs; the folder icons, D64), dconf
# and gsettings (GTK's dark or light, D65). niri itself comes from the system.
  runtime = [ matugen brightnessctl pipewire dbus systemd procps coreutils gnused dconf glib bash ];
in
stdenv.mkDerivation {
  pname = "rutile-shell";
  version = "0.8.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Makefile
      ../bin
      ../native
      ../shell
      ../share
      ../widgets/examples
      ../theme/apps
      ../theme/templates
      ../theme/roles.json
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

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
    mkdir -p $out/share/rutile/widgets && cp -r widgets/examples $out/share/rutile/widgets/
    install -Dm755 build/rutile-pywalfox-host $out/share/rutile/build/rutile-pywalfox-host
    install -Dm755 bin/rutile-shell $out/share/rutile/bin/rutile-shell
    # the Settings app in app launchers, run by this package's own CLI
    install -Dm644 share/applications/rutile-settings.desktop $out/share/applications/rutile-settings.desktop
    substituteInPlace $out/share/applications/rutile-settings.desktop \
      --replace-fail "Exec=rutile-shell " "Exec=$out/bin/rutile-shell "
    makeWrapper $out/share/rutile/bin/rutile-shell $out/bin/rutile-shell \
      --set RUTILE_SHELL_QML $out/share/rutile/shell/shell.qml \
      --set RUTILE_CLI $out/bin/rutile-shell \
      --prefix PATH : ${lib.makeBinPath ([ quickshell ] ++ runtime)} \
      --set FONTCONFIG_FILE ${fontsConf} \
      --suffix XDG_DATA_DIRS : ${papirus-icon-theme}/share
    runHook postInstall
  '';

  meta = {
    description = "A Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";
    mainProgram = "rutile-shell";
    platforms = lib.platforms.linux;
  };
}
