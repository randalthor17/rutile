# The greeter on a real system (plan 6.2, D97), in a NixOS VM: greetd and PAM for real; typing the password signs alice
# in, greetd starts her niri session, and the greeter remembers her. niri cannot draw in a VM (it needs a GPU; the VM
# has none), so here the greeter runs under sway on its software renderer instead of the module's niri, and alice's
# remembered session is a stand-in that records who ran it (her niri session would end at once without a GPU).
#   nix build .#checks.x86_64-linux.greeter -L     (needs KVM; screenshots in result/)
{ pkgs, greeterModule }:
let
  marker = pkgs.runCommand "marker-session" { passthru.providedSessions = [ "marker" ]; } ''
    mkdir -p $out/share/wayland-sessions $out/bin
    printf '#!/bin/sh\nid -un > /var/tmp/session-user\nexec sleep 600\n' > $out/bin/marker-session
    chmod +x $out/bin/marker-session
    printf '[Desktop Entry]\nName=Marker\nExec=%s\n' $out/bin/marker-session > $out/share/wayland-sessions/marker.desktop
  '';
in
pkgs.testers.runNixOSTest {
  name = "rutile-greeter";
  nodes.machine =
    { config, lib, pkgs, ... }:
    {
      imports = [ greeterModule ];
      programs.niri.enable = true;
      programs.rutile.greeter.enable = true;
      users.users.alice = {
        isNormalUser = true;
        description = "Alice Liddell";
        password = "wonderland";
      };
      hardware.graphics.enable = true;
      services.displayManager.sessionPackages = [ marker ];
      # alice's last session, as the greeter remembers it
      systemd.tmpfiles.rules = [
        ''f /var/lib/rutile-greeter/state.json 0640 greeter greeter - {"lastUser":"alice","sessions":{"alice":"marker"}}''
      ];
      services.greetd.settings.default_session.command = lib.mkForce (
        "${pkgs.systemd}/bin/systemd-cat -t rutile-greeter ${pkgs.sway}/bin/sway -c ${pkgs.writeText "greeter-sway.conf" ''
          exec "${config.programs.rutile.greeter.script}; ${pkgs.sway}/bin/swaymsg exit"
        ''}"
      );
      environment.sessionVariables.WLR_RENDERER = "pixman";
      systemd.services.greetd.environment.WLR_RENDERER = "pixman";
      virtualisation.memorySize = 2048;
      virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
    };
  testScript = ''
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -u greeter -f greeter.qml", timeout=120)
    machine.sleep(5)
    machine.screenshot("greeter")
    # a wrong password first: greetd says no, and the greeter asks again
    machine.send_chars("wrong\n")
    machine.sleep(6)
    machine.screenshot("wrong")
    machine.succeed("pgrep -u greeter -f greeter.qml")
    machine.fail("test -e /var/tmp/session-user")
    machine.send_chars("wonderland\n")
    machine.wait_until_succeeds("test -e /var/tmp/session-user", timeout=60)
    machine.succeed("grep -qx alice /var/tmp/session-user")
    machine.succeed("grep -q '\"alice\":\"marker\"' /var/lib/rutile-greeter/state.json")
    machine.succeed("! pgrep -u greeter -f greeter.qml")
  '';
}
