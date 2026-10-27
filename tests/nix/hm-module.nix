# Evaluates nix/home-manager.nix with stand-ins for the home-manager options it sets (tests/test_home_manager.py):
# what the shell's service, packages, files and niri configuration come out as. `niriModule`: whether home-manager's
# own niri module is there (and on).
{ module, cfg, niriModule ? false, package ? null }:
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  fontPkg = pkgs.writeTextDir "share/fonts/x.ttf" "";
  pkg = if package != null then package else
    pkgs.writeShellScriptBin "rutile-shell" "exit 0" // { meta.mainProgram = "rutile-shell"; };
  anything = lib.mkOption { type = lib.types.anything; default = { }; };
  stub = { lib, ... }: {
    options = {
      xdg.configHome = lib.mkOption { type = lib.types.str; default = "/home/test/.config"; };
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule { options.source = lib.mkOption { type = lib.types.path; }; });
        default = { };
      };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
      systemd.user.services = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      # home-manager's gtk, qt and fontconfig options, as plain values (programs.rutile.theming sets them)
      gtk = anything;
      qt = anything;
      fonts = anything;
    } // lib.optionalAttrs niriModule {
      wayland.windowManager.niri = {
        enable = lib.mkOption { type = lib.types.bool; default = false; };
        extraConfig = lib.mkOption { type = lib.types.lines; default = ""; };
      };
    };
  };
  eval = lib.evalModules {
    modules = [ module stub { programs.rutile = cfg; } { programs.rutile.package = lib.mkDefault pkg; }
                { programs.rutile.theming.fonts.package = lib.mkDefault fontPkg; } ]
      ++ lib.optional niriModule { wayland.windowManager.niri.enable = true; };
    specialArgs = { inherit pkgs; };
  };
  c = eval.config;
in
builtins.toJSON {
  failed = map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);
  packages = map (p: p.name) c.home.packages;
  service = c.systemd.user.services.rutile-shell or null;
  files = builtins.attrNames c.xdg.configFile;
  niriFile = if c.xdg.configFile ? "niri/rutile.kdl" then c.programs.rutile.niri.config else null;
  extraConfig = if niriModule then c.wayland.windowManager.niri.extraConfig else null;
  included = if niriModule && c.wayland.windowManager.niri.extraConfig != "" then c.programs.rutile.niri.config else null;
  exe = lib.getExe pkg;
  gtk = c.gtk;
  qt = c.qt;
  fonts = c.fonts;
  managed = c.programs.rutile.settings.appColors;
}
