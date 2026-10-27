# Rutile Shell as a package (plan 6.1): the QML shell, the theme templates it renders from, the compiled Firefox
# host (D54), and `rutile-shell`, which runs it under Quickshell with everything it calls on PATH and its fonts
# visible to Qt. `rutile-shell ipc call lock lock` and the like reach the running shell (Quickshell's own CLI).
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
  bash,
  material-symbols,
  google-sans-flex,
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
  # before sleep, LockedHint), pkill (apps' reload), sh and coreutils (file jobs). niri itself comes from the system.
  runtime = [ matugen brightnessctl pipewire dbus systemd procps coreutils bash ];
in
stdenv.mkDerivation {
  pname = "rutile-shell";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Makefile
      ../native
      ../shell
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
    install -Dm755 build/rutile-pywalfox-host $out/share/rutile/build/rutile-pywalfox-host
    makeWrapper ${lib.getExe quickshell} $out/bin/rutile-shell \
      --add-flags "-p $out/share/rutile/shell/shell.qml" \
      --prefix PATH : ${lib.makeBinPath runtime} \
      --set FONTCONFIG_FILE ${fontsConf}
    runHook postInstall
  '';

  meta = {
    description = "A Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";
    mainProgram = "rutile-shell";
    platforms = lib.platforms.linux;
  };
}
