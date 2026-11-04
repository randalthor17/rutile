# Joining a hidden Wi-Fi network (plan 2.6, D100), in a NixOS VM with a simulated radio (mac80211_hwsim): hostapd
# offers a network that does not broadcast its name on wlan0, NetworkManager is the client on wlan1, and the shell's
# own script (shell/services/hidden-wifi.sh, as Quick Settings runs it) joins it. A wrong password leaves nothing
# saved; the right one is kept by NetworkManager, so the network comes back after a disconnect without asking.
#   nix build .#checks.x86_64-linux.hidden-wifi -L     (needs KVM)
{ pkgs }:
let
  script = ../../shell/services/hidden-wifi.sh;
  password = "it's a $ecret; with spaces";
in
pkgs.testers.runNixOSTest {
  name = "rutile-hidden-wifi";
  nodes.machine =
    { lib, ... }:
    {
      boot.kernelModules = [ "mac80211_hwsim" ];
      services.hostapd = {
        enable = true;
        radios.wlan0 = {
          band = "2g";
          channel = 6;
          countryCode = "US";
          networks.wlan0 = {
            ssid = "rutile hidden";
            ignoreBroadcastSsid = "empty";
            authentication = {
              mode = "wpa2-sha256";
              wpaPassword = password;
            };
            bssid = "02:00:00:00:00:00";
          };
          # an open one, hidden too
          networks.wlan0-1 = {
            ssid = "rutile open";
            ignoreBroadcastSsid = "empty";
            authentication.mode = "none";
            bssid = "02:00:00:00:00:01";
          };
        };
      };
      # addresses for the client, as a router behind the access point gives them (NetworkManager waits for one)
      networking.interfaces.wlan0.ipv4.addresses = [ { address = "192.168.50.1"; prefixLength = 24; } ];
      networking.interfaces.wlan0-1.ipv4.addresses = [ { address = "192.168.51.1"; prefixLength = 24; } ];
      networking.firewall.trustedInterfaces = [ "wlan0" "wlan0-1" ];       # DHCP's requests reach dnsmasq
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          port = 0;
          bind-dynamic = true;
          interface = [ "wlan0" "wlan0-1" ];
          dhcp-range = [ "192.168.50.10,192.168.50.100" "192.168.51.10,192.168.51.100" ];
        };
      };
      networking.networkmanager = {
        enable = true;
        unmanaged = [ "wlan0" "wlan0-1" ];
        logLevel = "INFO";
      };
      # qemu-vm.nix turns wpa_supplicant off; NetworkManager needs it on (it drives it over D-Bus)
      networking.wireless.enable = lib.mkOverride 0 true;
      environment.etc."hidden-wifi.sh".source = script;
    };

  testScript = ''
    import shlex
    machine.wait_for_unit("hostapd.service")
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_until_succeeds("nmcli -t -f DEVICE,STATE device | grep -q '^wlan1:disconnected'")

    def join(name, security, stdin=""):
        cmd = f"printf %s {shlex.quote(stdin)} | sh /etc/hidden-wifi.sh {shlex.quote(name)} {security}"
        return machine.execute(cmd, timeout=150)

    with subtest("A hidden network is not in the scan"):
        machine.succeed("nmcli device wifi rescan ifname wlan1 || true")
        machine.sleep(3)
        machine.fail("nmcli -t -f SSID device wifi list ifname wlan1 | grep -q 'rutile hidden'")

    with subtest("A wrong password fails and leaves no connection"):
        status, out = join("rutile hidden", "psk", "not the password\n")
        assert status != 0, out
        machine.fail("nmcli connection show id 'rutile hidden'")

    with subtest("A name that is not there fails and leaves no connection"):
        status, out = join("nowhere", "open")
        assert status != 0, out
        machine.fail("nmcli connection show id nowhere")

    with subtest("Bad arguments are refused before anything is added"):
        status, out = join("", "open")
        assert status == 2, out
        status, out = join("x", "wep")
        assert status == 2, out
        machine.fail("nmcli connection show id x")

    with subtest("The right password joins, as a hidden network"):
        status, out = join("rutile hidden", "psk", ${builtins.toJSON password} + "\n")
        assert status == 0, out
        machine.succeed("nmcli -t -f GENERAL.STATE connection show id 'rutile hidden' | grep -q activated")
        assert machine.succeed("nmcli -g 802-11-wireless.hidden connection show id 'rutile hidden'").strip() == "yes"

    with subtest("NetworkManager kept the password: it joins again without one"):
        machine.succeed("nmcli connection down id 'rutile hidden'")
        machine.succeed("nmcli --wait 90 connection up id 'rutile hidden' </dev/null")
        saved = machine.succeed("nmcli -s -g 802-11-wireless-security.psk connection show id 'rutile hidden'").strip()
        assert saved == ${builtins.toJSON password}, saved

    with subtest("Joining again reuses the saved connection"):
        machine.succeed("nmcli connection down id 'rutile hidden'")
        status, out = join("rutile hidden", "psk", ${builtins.toJSON password} + "\n")
        assert status == 0, out
        count = machine.succeed("nmcli -t -f NAME connection show | grep -c '^rutile hidden$'").strip()
        assert count == "1", count

    with subtest("An open hidden network joins without a password"):
        status, out = join("rutile open", "open")
        assert status == 0, out
        machine.succeed("nmcli -t -f GENERAL.STATE connection show id 'rutile open' | grep -q activated")
  '';
}
