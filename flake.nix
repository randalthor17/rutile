{
  description = "Rutile Shell: a Quickshell desktop shell for niri with a Googlebook-style Material 3 Expressive look";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Google Sans Flex is not in nixpkgs; this is our own package (OFL-1.1).
      googleSansFlex = pkgs: pkgs.callPackage ./nix/googlesans-flex.nix { };
    in
    {
      # Ollama as a NixOS service on the AMD GPU (see nix/local-ai-module.nix and docs/sidework.md).
      nixosModules.local-ai = import ./nix/local-ai-module.nix;

      packages = forAllSystems (pkgs: {
        google-sans-flex = googleSansFlex pkgs;
      });

      # `nix develop` gives everything `make check` needs, with Qt's QML modules on
      # the import path (a bare qtdeclarative in a shell does not set it up) and the
      # fonts Rutile depends on visible to Qt.
      devShells = forAllSystems (
        pkgs:
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
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
          # ROCm only exists on x86_64, so this shell is not offered elsewhere.

          # `nix develop .#local-ai`: the local-model side-work tools. Kept separate because the ROCm
          # build of Ollama is a multi-gigabyte closure the everyday shell should not pull in.
          local-ai = pkgs.mkShell {
            name = "rutile-local-ai";
            packages = [
              pkgs.git
              pkgs.gnumake
              python
              pkgs.ollama-rocm # server + client with ROCm; use pkgs.ollama-vulkan if ROCm fails on the card
              pkgs.opencode # terminal coding agent (2.x); talks to Ollama through its OpenAI-compatible API
              pkgs.radeontop # GPU load while a model runs
              # Claude Code is unfree: allow exactly this package, not unfree software in general.
              (import nixpkgs {
                inherit (pkgs.stdenv.hostPlatform) system;
                config.allowUnfreePredicate = pkg: lib.getName pkg == "claude-code";
              }).claude-code
            ];
            shellHook = ''
              echo "rutile local-ai shell: python3 tools/sidework.py models | serve | start TASK | agent TASK"
            '';
          };
        }
      );
    };
}
