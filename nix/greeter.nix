# Rutile's greeter as the system's sign-in screen (plan 6.2, D97): greetd runs a niri of its own whose one job is to
# start `rutile-shell greeter` and quit when it does; greetd then starts the session that was chosen.
#
#   imports = [ inputs.rutile.nixosModules.greeter ];
#   programs.rutile.greeter.enable = true;
#   programs.rutile.greeter.wallpaper = ./wall.jpg;     # optional; the greeter cannot read anyone's home
#
# The sessions offered are the system's (services.displayManager: niri's, with programs.niri.enable). Who signed in
# last, into which session, is kept in /var/lib/rutile-greeter.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rutile.greeter;
  niri = cfg.niriPackage;
  stateDir = "/var/lib/rutile-greeter";
  greeter = pkgs.writeShellScript "rutile-greeter" ''
    export RUTILE_GREETER_STATE=${stateDir}/state.json
    export RUTILE_SESSION_DIRS=${config.services.displayManager.sessionData.desktops}/share
    export RUTILE_PALETTE=${cfg.palette}
    export XDG_CACHE_HOME=${stateDir}/cache
    ${lib.optionalString (cfg.wallpaper != null) "export RUTILE_GREETER_WALLPAPER=${cfg.wallpaper}"}
    ${lib.getExe cfg.package} greeter
    ${lib.getExe niri} msg action quit --skip-confirmation
  '';
  niriConfig = pkgs.writeText "rutile-greeter-niri.kdl" ''
    hotkey-overlay {
        skip-at-startup
    }
    prefer-no-csd
    spawn-at-startup "${greeter}"
  '';
in
{
  options.programs.rutile.greeter = {
    enable = lib.mkEnableOption "Rutile's greeter on greetd, in a niri of its own, as the sign-in screen";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The Rutile Shell package whose greeter runs (the flake's own by default).";
    };
    niriPackage = lib.mkOption {
      type = lib.types.package;
      default = config.programs.niri.package or pkgs.niri;
      defaultText = lib.literalExpression "config.programs.niri.package or pkgs.niri";
      description = "The niri the greeter runs in.";
    };
    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "The image behind the sign-in screen (copied to the Nix store, where the greeter can read it); null: a plain surface.";
    };
    script = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = greeter;
      description = "What the greeter's niri starts: the greeter, then niri's quit (the VM test runs it under sway).";
    };
    palette = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.package}/share/rutile/theme/fixtures/palette-134aae-tonal-spot-dark.json";
      defaultText = lib.literalExpression ''"''${package}/share/rutile/theme/fixtures/palette-134aae-tonal-spot-dark.json"'';
      description = "The colors (a palette.json, as the shell's in ~/.cache/rutile; copy yours to match your desktop).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings.default_session = {
        user = "greeter";
        # its log to the journal (journalctl -t rutile-greeter), not over the console it starts on
        command = "${pkgs.systemd}/bin/systemd-cat -t rutile-greeter ${lib.getExe niri} -c ${niriConfig}";
      };
    };
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 greeter greeter - -"
      "d ${stateDir}/cache 0750 greeter greeter - -"
    ];
  };
}
