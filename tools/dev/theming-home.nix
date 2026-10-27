# A home-manager generation with programs.rutile.theming on, for tools/dev/theming_check.py (D59): home-manager's
# real gtk, qt, fontconfig and dconf modules, a user whose home is the check's sandbox folder.
#   nix-build tools/dev/theming-home.nix --arg homeManager /nix/store/...-source --argstr home /tmp/x/home
{ homeManager, home, flake ? builtins.getFlake (toString ../..), system ? builtins.currentSystem, theming ? true,
  plainGtk4 ? false }:
let
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  hm = import "${homeManager}/modules" {
    inherit pkgs;
    configuration = {
      imports = [ flake.homeManagerModules.default ];
      home.username = "rutile-check";
      home.homeDirectory = home;
      home.stateVersion = "26.05";
      programs.rutile.enable = true;
      programs.rutile.systemd.enable = false;
      programs.rutile.theming.enable = theming;
      programs.rutile.theming.gtk.plainGtk4 = plainGtk4;
    };
  };
in
hm.activationPackage
