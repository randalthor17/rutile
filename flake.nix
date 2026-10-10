{
  description = "Rutile Shell: a Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Google Sans Flex is not in nixpkgs; this is our own package (OFL-1.1).
      googleSansFlex = pkgs: pkgs.callPackage ./nix/googlesans-flex.nix { };
    in
    {
      packages = forAllSystems (pkgs: {
        google-sans-flex = googleSansFlex pkgs;
      });

      # `nix develop` gives everything `make check` needs, with Qt's QML modules on
      # the import path (a bare qtdeclarative in a shell does not set it up) and the
      # fonts Rutile depends on visible to Qt.
      devShells = forAllSystems (pkgs:
        let
          inherit (pkgs) lib;
          qt = pkgs.qt6;
          qmlPath = lib.makeSearchPath qt.qtbase.qtQmlPrefix [ qt.qtdeclarative ];
          fontDirs = lib.concatStringsSep ":" [
            "${googleSansFlex pkgs}/share/fonts"
            "${pkgs.material-symbols}/share/fonts"
          ];
          # materialyoucolor is only used by an optional test cross-check; include it when nixpkgs has it.
          python = pkgs.python3.withPackages (ps: lib.optional (ps ? materialyoucolor) ps.materialyoucolor);
        in
        {
          default = pkgs.mkShell {
            name = "rutile-dev";
            packages = [
              pkgs.git
              pkgs.gnumake
              python
              pkgs.matugen
              qt.qtdeclarative # qmltestrunner, qmllint and the QML modules
              pkgs.quickshell
            ];
            shellHook = ''
              export QML2_IMPORT_PATH=${qmlPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
              # Deliberately no QT_QPA_PLATFORM here: tools/qtws.py sets offscreen for tests only,
              # so Quickshell launched from this shell still opens real windows.
              export RUTILE_FONT_DIRS=${fontDirs}
              # Add those font dirs on top of the system fontconfig (it is included, nothing is lost).
              if root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -f "$root/tools/fontconf.py" ]; then
                if conf=$(python3 "$root/tools/fontconf.py" write); then
                  export FONTCONFIG_FILE="$conf"
                fi
              fi
              echo "rutile dev shell: run 'make check'"
            '';
          };
        });
    };
}
