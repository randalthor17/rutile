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

      # programs.rutile: the shell as a user service, its niri rules and binds, and its settings (D45, D55,
      # nix/home-manager.nix). The package defaults to this flake's.
      homeManagerModules.default =
        { lib, pkgs, ... }:
        {
          imports = [ ./nix/home-manager.nix ];
          programs.rutile.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };

      packages = forAllSystems (pkgs: rec {
        # Rutile Shell: `nix run .` starts it (D55, nix/package.nix).
        default = rutile-shell;
        rutile-shell = pkgs.callPackage ./nix/package.nix { google-sans-flex = googleSansFlex pkgs; };
        google-sans-flex = googleSansFlex pkgs;
        # The Firefox colors' native-messaging host (D54), the shell's one compiled program.
        pywalfox-host = pkgs.stdenv.mkDerivation {
          pname = "rutile-pywalfox-host";
          version = "0.1.0";
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [ ./Makefile ./native ];
          };
          buildPhase = "make native CC=$CC";
          installPhase = "install -Dm755 build/rutile-pywalfox-host $out/bin/rutile-pywalfox-host";
          meta.mainProgram = "rutile-pywalfox-host";
        };
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
          # Test cross-checks only, never imported by the tools: materialyoucolor (palette, when nixpkgs has
          # it) and jsonschema (tools/widget_check.py, D29), so those tests run instead of skipping.
          python = pkgs.python3.withPackages (
            ps: [ ps.jsonschema ] ++ lib.optional (ps ? materialyoucolor) ps.materialyoucolor
          );

          # The everyday shell's tools and setup, shared by every shell: an agent in local-ai must be
          # able to run `make check` and the brief's acceptance check without leaving it.
          devPackages = [
            pkgs.git
            pkgs.gnumake
            python
            pkgs.matugen
            qt.qtdeclarative # qmltestrunner, qmllint and the QML modules
            pkgs.quickshell
            pkgs.brightnessctl # the shell's backlight control at run time (D39)
            pkgs.sway # test only: a headless compositor for `qtws.py test-wayland` (D40)
            pkgs.grim # test only: screenshots of that compositor
            pkgs.pipewire # pw-play: the notification sound at run time (plan 2.8)
            pkgs.libnotify # test only: notify-send, to send the shell notifications (plan 2.8)
          ];
          devHook = ''
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
          '';
        in
        {
          default = pkgs.mkShell {
            name = "rutile-dev";
            packages = devPackages;
            shellHook = devHook + ''
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
            packages = devPackages ++ [
              pkgs.ollama-rocm # server + client with ROCm; use pkgs.ollama-vulkan if ROCm fails on the card
              pkgs.opencode # terminal coding agent (2.x); talks to Ollama through its OpenAI-compatible API
              pkgs.radeontop # GPU load while a model runs
              # Claude Code is unfree: allow exactly this package, not unfree software in general.
              (import nixpkgs {
                inherit (pkgs.stdenv.hostPlatform) system;
                config.allowUnfreePredicate = pkg: lib.getName pkg == "claude-code";
              }).claude-code
              pkgs.nodejs_22 # some local MCPs
            ];
            shellHook = devHook + ''
              echo "rutile local-ai shell: python3 tools/sidework.py models | serve | start TASK | agent TASK"
            '';
          };
        }
      );
    };
}
