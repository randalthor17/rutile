# Home-manager module for Rutile Shell (plan 6.1, D45, D55).
#
#   programs.rutile.enable = true;     the shell as a systemd user service in the graphical session, the
#                                      `rutile-shell` command (rutile-shell ipc call lock lock), and niri's side:
#                                      a layer rule so the power menu and the password dialog blur windows, not
#                                      only the wallpaper, and (opt-in) keybinds for the shell. With home-manager's
#                                      niri module on, that goes into your config.kdl as an `include`, checked
#                                      by `niri validate` at build time; otherwise it is ~/.config/niri/rutile.kdl
#                                      and you add `include "rutile.kdl"` yourself.
#   programs.rutile.settings.*         the shell's settings in Nix. The options are built from settings/schema.json,
#                                      the schema the shell checks against, so they are type checked here. What
#                                      you set goes to $XDG_CONFIG_HOME/rutile/managed.json, read-only; the shell
#                                      gives it priority and does not let those keys change. Unset (null) options
#                                      stay the shell's to change. Works without `enable`.
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rutile;
  json = pkgs.formats.json { };
  schema = builtins.fromJSON (builtins.readFile ../settings/schema.json);

  leafType =
    s:
    if s ? enum then
      lib.types.enum s.enum
    else if s.type == "boolean" then
      lib.types.bool
    else if s.type == "integer" then
      bounded lib.types.int s
    else if s.type == "number" then
      bounded lib.types.number s
    else if s.type == "string" then
      lib.types.str
    else if s.type == "array" then
      lib.types.listOf (leafType s.items)
    else
      throw "rutile: settings/schema.json: unsupported type ${builtins.toJSON s.type}";

  # minimum and maximum, as the shell checks them
  bounded =
    type: s:
    if s ? minimum || s ? maximum then
      lib.types.addCheck type (v: (!(s ? minimum) || v >= s.minimum) && (!(s ? maximum) || v <= s.maximum))
      // {
        description = "${type.description} between ${toString (s.minimum or "-inf")} and ${toString (s.maximum or "inf")}";
      }
    else
      type;

  optionsFor = s: lib.mapAttrs (_: p: if p.type == "object" then optionsFor p else leafOption p) s.properties;
  leafOption =
    p:
    lib.mkOption {
      type = lib.types.nullOr (leafType p);
      default = null;
      description =
        lib.concatStringsSep " " (lib.filter (x: x != "") [ (p.title or "") (p.description or "") ])
        + lib.optionalString (p ? default) " The shell's default: ${builtins.toJSON p.default}.";
    };

  # the settings that were set: no nulls, no empty objects
  prune =
    v:
    lib.filterAttrs (_: x: x != null && x != { }) (
      lib.mapAttrs (_: x: if builtins.isAttrs x then prune x else x) v
    );
  managed = prune cfg.settings;

  exe = lib.getExe cfg.package;
  # A bind that calls the shell over IPC; media keys work while the screen is locked.
  bind =
    key: args:
    let
      locked = lib.hasPrefix "XF86" key;
    in
    "    ${key}${lib.optionalString locked " allow-when-locked=true"} { spawn ${
      lib.concatMapStringsSep " " builtins.toJSON ([ exe "ipc" "call" ] ++ args)
    }; }";
  niriText = (
    ''
      // Rutile Shell's part of niri's configuration (written by home-manager, programs.rutile.niri).
      // The power menu and the polkit dialog blur what is behind them, windows too (niri's xray blurs only the
      // wallpaper for layer surfaces).
      layer-rule {
          match namespace="^rutile-(power|polkit)$"
          background-effect {
              xray false
          }
      }
    ''
    + lib.optionalString cfg.niri.binds.enable ''
      binds {
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList bind cfg.niri.binds.keys)}
      }
    ''
  );
  niriConfig = pkgs.writeText "rutile.kdl" niriText;
  hasNiriModule = options ? wayland && options.wayland ? windowManager && options.wayland.windowManager ? niri;
  niriModuleOn = hasNiriModule && config.wayland.windowManager.niri.enable;
  niriOn = cfg.enable && cfg.niri.enable;
in
{
  options.programs.rutile = {
    enable = lib.mkEnableOption "Rutile Shell, a Quickshell desktop shell for niri";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The Rutile Shell package (the flake's module sets it to the flake's own).";
    };

    systemd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the shell as a systemd user service that starts with the graphical session.";
      };
      target = lib.mkOption {
        type = lib.types.str;
        default = "graphical-session.target";
        description = "The systemd user target the shell starts with (niri-session starts graphical-session.target).";
      };
    };

    niri = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add Rutile's part of niri's configuration (the blur layer rule, and the binds if enabled).";
      };
      binds = {
        enable = lib.mkEnableOption ''
          keybinds for the shell (off by default: they replace binds of yours on the same keys, which win
          otherwise only if they come later)'';
        keys = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.str);
          default = {
            XF86AudioRaiseVolume = [ "osd" "volumeUp" ];
            XF86AudioLowerVolume = [ "osd" "volumeDown" ];
            XF86AudioMute = [ "osd" "toggleMute" ];
            XF86MonBrightnessUp = [ "osd" "brightnessUp" ];
            XF86MonBrightnessDown = [ "osd" "brightnessDown" ];
            "Mod+Alt+L" = [ "lock" "lock" ];
            "Mod+Alt+P" = [ "power" "toggle" ];
            "Mod+Alt+S" = [ "settings" "toggle" ];
            "Mod+Space" = [ "launcher" "toggle" ];
          };
          description = "Keys and the shell IPC call each makes (`rutile-shell ipc call <target> <function> [args]`).";
        };
      };
    };

    settings = optionsFor schema;

    niri.config = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      default = niriText;
      description = "The KDL Rutile adds to niri's configuration (to look at; set the options above instead).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (managed != { }) {
      xdg.configFile."rutile/managed.json".source = json.generate "rutile-managed.json" managed;
    })

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "programs.rutile.package is not set; use the flake's homeManagerModules.default, which sets it.";
        }
      ];
      home.packages = lib.optional (cfg.package != null) cfg.package;
      systemd.user.services.rutile-shell = lib.mkIf (cfg.systemd.enable && cfg.package != null) {
        Unit = {
          Description = "Rutile Shell";
          PartOf = [ cfg.systemd.target ];
          After = [ cfg.systemd.target ];
          Requisite = [ cfg.systemd.target ];
        };
        Service = {
          ExecStart = exe;
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ cfg.systemd.target ];
      };
    })

    # niri's part: into home-manager's niri config when that module is on (validated there), else a file to include
    (lib.mkIf (niriOn && !niriModuleOn) {
      xdg.configFile."niri/rutile.kdl".source = niriConfig;
    })
    (lib.optionalAttrs hasNiriModule {
      wayland.windowManager.niri.extraConfig = lib.mkIf (niriOn && niriModuleOn) (
        lib.mkAfter ''include "${niriConfig}"''
      );
    })
  ];
}
