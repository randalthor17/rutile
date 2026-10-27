# Evaluates nix/home-manager.nix with a stand-in for home-manager's xdg.configFile (tests/test_home_manager.py).
{ module, settings }:
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  stub = { lib, ... }: {
    options.xdg.configFile = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { options.source = lib.mkOption { type = lib.types.path; }; }); default = { }; };
    options.home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
    options.systemd.user.services = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    options.assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
  };
  eval = lib.evalModules {
    modules = [ module stub { programs.rutile.settings = settings; } ];
    specialArgs = { inherit pkgs; };
  };
  files = eval.config.xdg.configFile;
in
if files ? "rutile/managed.json" then builtins.readFile files."rutile/managed.json".source else "none"
