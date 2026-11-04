# Rutile's greeter as the system's sign-in screen (plan 6.2, D97): greetd runs a niri of its own whose one job is to
# start `rutile-shell greeter` and quit when it does; greetd then starts the session that was chosen.
#
#   imports = [ inputs.rutile.nixosModules.greeter ];
#   services.displayManager.rutile-greeter.enable = true;
#   services.displayManager.rutile-greeter.wallpaper = ./wall.jpg;     # optional: before anyone has signed in
#
# The sessions offered are the system's (services.displayManager: niri's, with programs.niri.enable). Each normal
# user gets /var/lib/rutile-greeter/users/<name>, theirs and readable by the greeter: their Rutile Shell copies its
# wallpaper and colors there, and the greeter shows them for that person (D98). The greeter's own state (who signed
# in last, into which session) is in /var/lib/rutile-greeter/greeter.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.displayManager.rutile-greeter;
  niri = cfg.niriPackage;
  stateDir = "/var/lib/rutile-greeter";
  people = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;
  greeter = pkgs.writeShellScript "rutile-greeter" ''
    export RUTILE_GREETER_STATE=${stateDir}/greeter/state.json
    export RUTILE_GREETER_USERS=${stateDir}/users
    export RUTILE_SESSION_DIRS=${config.services.displayManager.sessionData.desktops}/share
    export RUTILE_PALETTE=${cfg.palette}
    export XDG_CACHE_HOME=${stateDir}/greeter/cache
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
  options.services.displayManager.rutile-greeter = {
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
      description = "The image behind the sign-in screen until someone has signed in with Rutile Shell (theirs shows after); null: Rutile's own.";
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
      description = "The colors until someone has signed in with Rutile Shell (theirs show after): a palette.json.";
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
    # the greeter's own, and one folder per person that their shell writes and the greeter reads
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root - -"
      "d ${stateDir}/greeter 0750 greeter greeter - -"
      "d ${stateDir}/greeter/cache 0750 greeter greeter - -"
      "d ${stateDir}/users 0755 root root - -"
    ]
    ++ lib.mapAttrsToList (name: u: "d ${stateDir}/users/${name} 0755 ${name} ${if u.group != "" then u.group else "users"} - -") people;
  };
}
