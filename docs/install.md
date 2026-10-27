# Installing Rutile Shell (Nix)

Rutile ships as a flake (plan 6.1, D55): the package, `rutile-shell`, and a home-manager module that runs it as a
user service and adds its part of niri's configuration. It is early: try it on a separate user first.

## Try it once, in the current session

```
nix run github:randalthor17/rutile
```

Not beside another running Rutile (or a second bar of another shell): stop that first.

## A user of its own (home-manager)

In the flake of your system or home configuration:

```nix
{
  inputs.rutile.url = "github:randalthor17/rutile";             # or path:/where/the/checkout/is for local changes
  inputs.rutile.inputs.nixpkgs.follows = "nixpkgs";

  # ...in the home-manager configuration of the test user:
  #   imports = [ inputs.rutile.homeManagerModules.default ];
}
```

and in that user's home-manager configuration:

```nix
{
  programs.rutile.enable = true;

  # Optional:
  programs.rutile.niri.binds.enable = true;              # media keys, Mod+Alt+L lock, Mod+Alt+P power, Mod+Alt+S settings,
                                                         # Mod+Space launcher; change them with niri.binds.keys
  programs.rutile.settings.wallpaper.path = "/home/test/Pictures/wall.png";   # any setting; set in Nix, it is
                                                         # locked in the shell's Settings
}
```

What `enable` gives:

- `rutile-shell`, which starts the shell and reaches a running one: `rutile-shell ipc call lock lock`,
  `rutile-shell ipc show` for every call.
- A systemd user service, `rutile-shell.service`, started with `graphical-session.target` (niri-session starts it)
  and stopped with it. `systemctl --user status rutile-shell`, `journalctl --user -u rutile-shell`.
  `programs.rutile.systemd.enable = false` if you would rather start it from niri's `spawn-at-startup`.
- niri's part (`programs.rutile.niri.enable`, on): a layer rule so the power menu and the password dialog blur
  your windows, not only the wallpaper, and the binds if you turned them on. With home-manager's niri module
  (`wayland.windowManager.niri.enable`), it is included into your config.kdl and checked by `niri validate` when
  you switch. Without it, it is `~/.config/niri/rutile.kdl`: add `include "rutile.kdl"` to your config.kdl.

The package brings what the shell runs (matugen, brightnessctl, pw-play, dbus-monitor, systemd's tools) and its
fonts (Google Sans Flex, Material Symbols, through its own fontconfig file that includes the system's).

## What the system needs

- niri, started as a session (`niri-session`, which the NixOS niri module does), so the graphical session target
  exists and `XDG_SESSION_ID` reaches the service (for `loginctl lock-session` and lock before sleep).
- PipeWire (sound, volume), NetworkManager (Wi-Fi), BlueZ (Bluetooth), UPower (battery): the usual NixOS desktop
  services; the shell leaves out what is missing.
- xdg-desktop-portal with a file chooser (GNOME's or GTK's; home-manager's niri module sets up GNOME's), for
  Settings' Choose... buttons.
- PAM's `login` service, for the lock screen (on NixOS by default).

## Things that clash with another shell

One program per session can own each of these; turn them off in the other shell (Noctalia, for example) or the
first one to start keeps them: notifications (`org.freedesktop.Notifications`), the polkit agent (Rutile's:
`programs.rutile.settings.polkit.agent = false` to leave it to the other), the wallpaper, and other apps' colors
(off in Rutile by default).
