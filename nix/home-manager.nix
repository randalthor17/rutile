# Home-manager module for Rutile Shell (plan 6.1, D45, D55).
#
#   programs.rutile.enable = true;     the shell as a systemd user service in the graphical session, the
#                                      `rutile-shell` command (rutile-shell ipc call lock lock), and niri's side:
#                                      a layer rule so the power menu and the password dialog blur windows, not
#                                      only the wallpaper, and (opt-in) keybinds for the shell. With home-manager's
#                                      niri module on, that goes into your config.kdl as an `include`, checked
#                                      by `niri validate` at build time; otherwise it is ~/.config/niri/rutile.kdl
#                                      and you add `include "rutile.kdl"` yourself.
#   programs.rutile.theming.enable     GTK, Qt and KDE apps set up to wear the shell's colors, its font and an icon
#                                      theme (D59): adw-gtk3 for GTK 3, a dark color scheme, gtk.css importing the
#                                      shell's colors, qt5ct/qt6ct with Fusion, kdeglobals' fonts, and the shell's
#                                      gtk, qt and kde color switches on. Each part has its own enable.
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
      // Window borders, focus ring and the like in the shell's colors, while Settings > Wallpaper > Colors in other
      // apps > niri is on: the shell writes this file, and removes it when off (niri's own colors then apply).
      include optional=true "${config.xdg.configHome}/niri/rutile-colors.kdl"
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

  th = cfg.theming;
  font = th.fonts;
  # QFont::toString: family, size, pixel size, style hint, weight, style, underline, strike out, fixed pitch, ...
  qt6Font = size: "${font.name},${toString size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
  qt5Font = size: "${font.name},${toString size},-1,5,50,0,0,0,0,0";
  # qt5ct/qt6ct read their files with QSettings, where an unquoted comma makes a list: quoted
  quoted = s: "\"${s}\"";
  qtctSettings = fontOf: {
    Appearance = {
      style = "Fusion";
      custom_palette = true;
    } // lib.optionalAttrs (th.icons.name != null) { icon_theme = th.icons.name; };
  } // lib.optionalAttrs font.enable {
    Fonts.general = quoted (fontOf font.size);
  };
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

    theming = {
      enable = lib.mkEnableOption ''
        GTK, Qt and KDE apps set up for the shell's colors (the gtk, qt and kde switches of Colors in other apps,
        turned on here and so locked in Settings), its font and an icon theme'';
      gtk.enable = lib.mkOption {
        type = lib.types.bool;
        default = th.enable;
        defaultText = lib.literalExpression "config.programs.rutile.theming.enable";
        description = ''
          GTK: adw-gtk3 (dark) for GTK 3 apps, so they use the named colors the shell overrides; libadwaita's own
          theme for GTK 4; a dark color scheme; gtk.css importing the shell's rutile.css.'';
      };
      gtk.plainGtk4 = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also theme GTK 4 apps that do not use libadwaita (they draw with GTK's own theme, whose colors are fixed):
          adw-gtk3's GTK 4 stylesheet, imported by gtk.css. It is loaded over libadwaita apps too, which home-manager
          warns may cause issues.'';
      };
      qt.enable = lib.mkOption {
        type = lib.types.bool;
        default = th.enable;
        defaultText = lib.literalExpression "config.programs.rutile.theming.enable";
        description = "Qt: qt5ct and qt6ct as the platform theme, with the Fusion style (it follows the palette).";
      };
      kde.enable = lib.mkOption {
        type = lib.types.bool;
        default = th.enable;
        defaultText = lib.literalExpression "config.programs.rutile.theming.enable";
        description = "KDE apps outside Plasma: the shell's colors in kdeglobals, and its fonts and icons there.";
      };
      fonts = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = th.enable;
          defaultText = lib.literalExpression "config.programs.rutile.theming.enable";
          description = "The shell's font for apps: GTK, Qt, KDE, and fontconfig's default sans-serif.";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Google Sans Flex";
          description = "The font family.";
        };
        size = lib.mkOption {
          type = lib.types.int;
          default = 11;
          description = "Its size in points.";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "The font's package (the flake's module sets Google Sans Flex).";
        };
      };
      icons = {
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "Adwaita";
          description = "Icon theme for GTK, Qt and KDE apps (null: leave it).";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.adwaita-icon-theme;
          defaultText = lib.literalExpression "pkgs.adwaita-icon-theme";
          description = "The icon theme's package.";
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

    # Apps in the shell's look (D59). The color files come from the shell (its switches, on here); this sets up
    # what makes the apps read them, and the font and icons.
    (lib.mkIf (th.gtk.enable || th.qt.enable || th.kde.enable) {
      programs.rutile.settings.appColors = {
        enabled = lib.mkDefault true;
        gtk = lib.mkIf th.gtk.enable (lib.mkDefault true);
        qt = lib.mkIf th.qt.enable (lib.mkDefault true);
        kde = lib.mkIf th.kde.enable (lib.mkDefault true);
      };
    })
    (lib.mkIf th.gtk.enable {
      gtk = {
        enable = true;
        colorScheme = "dark";
        theme = lib.mkDefault {
          name = "adw-gtk3-dark";
          package = pkgs.adw-gtk3;
        };
        # libadwaita's own, with the shell's colors over it; adw-gtk3's (imported before ours) for plain GTK 4
        gtk4.theme = lib.mkDefault (
          if th.gtk.plainGtk4 then
            {
              name = "adw-gtk3-dark";
              package = pkgs.adw-gtk3;
            }
          else
            null
        );
        # absolute: home-manager's gtk.css is a link into the store
        gtk3.extraCss = ''@import url("file://${config.xdg.configHome}/gtk-3.0/rutile.css");'';
        gtk4.extraCss = ''@import url("file://${config.xdg.configHome}/gtk-4.0/rutile.css");'';
        font = lib.mkIf font.enable {
          inherit (font) name size package;
        };
        iconTheme = lib.mkIf (th.icons.name != null) {
          inherit (th.icons) name package;
        };
      };
    })
    (lib.mkIf th.qt.enable {
      qt = {
        enable = true;
        platformTheme.name = "qtct"; # QT_QPA_PLATFORMTHEME=qt5ct, which qt6ct answers too
      };
      # written into their (mutable) files at activation: the shell sets the color keys in the same files
      qt.kde.settings = {
        "qt5ct/qt5ct.conf" = qtctSettings qt5Font;
        "qt6ct/qt6ct.conf" = qtctSettings qt6Font;
      };
    })
    (lib.mkIf th.kde.enable {
      qt.kde.settings.kdeglobals =
        lib.optionalAttrs font.enable {
          General = {
            font = qt6Font font.size;
            menuFont = qt6Font font.size;
            toolBarFont = qt6Font (font.size - 1);
            smallestReadableFont = qt6Font (font.size - 2);
          };
          WM.activeFont = qt6Font font.size;
        }
        // lib.optionalAttrs (th.icons.name != null) { Icons.Theme = th.icons.name; };
    })
    (lib.mkIf (th.fonts.enable && (th.gtk.enable || th.qt.enable || th.kde.enable)) {
      fonts.fontconfig = {
        enable = true;
        defaultFonts.sansSerif = [ font.name ];
      };
      home.packages = lib.optional (font.package != null) font.package
        ++ lib.optional (th.icons.package != null && th.icons.name != null) th.icons.package;
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
