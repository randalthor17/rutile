{
  description = "Rutile Shell: a Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # `nix develop` gives everything `make check` needs, with Qt's QML modules on
      # the import path (a bare qtdeclarative in a shell does not set it up).
      devShells = forAllSystems (pkgs:
        let
          inherit (pkgs) lib;
          qt = pkgs.qt6;
          qmlPath = lib.makeSearchPath qt.qtbase.qtQmlPrefix [ qt.qtdeclarative ];
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
              echo "rutile dev shell: run 'make check'"
            '';
          };
        });
    };
}
