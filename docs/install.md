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

- `rutile-shell`, which starts the shell and reaches a running one: `rutile-shell lock lock`,
  `rutile-shell osd volumeUp`. `rutile-shell --help` lists every call with its arguments; `rutile-shell ipc`
  asks the running shell what it answers.
- A systemd user service, `rutile-shell.service`, started with `graphical-session.target` (niri-session starts it)
  and stopped with it. `systemctl --user status rutile-shell`, `journalctl --user -u rutile-shell`.
  `programs.rutile.systemd.enable = false` if you would rather start it from niri's `spawn-at-startup`.
- niri's part (`programs.rutile.niri.enable`, on): a layer rule so the power menu and the password dialog blur
  your windows, not only the wallpaper, the binds if you turned them on, and
  `include optional=true "~/.config/niri/rutile-colors.kdl"` (written out in full), which gives niri the shell's
  colors while Settings > Wallpaper > Colors in other apps > niri is on (the file is missing otherwise, and niri
  keeps its own). With home-manager's niri module
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

## GTK, Qt and KDE apps in the shell's look

```nix
programs.rutile.theming.enable = true;
```

sets up GTK (adw-gtk3 dark for GTK 3 apps and for GTK 4 apps without libadwaita, libadwaita's own theme for the
rest, a dark color scheme, gtk.css importing the shell's colors), Qt (qt5ct and qt6ct with the Breeze style;
`theming.qt.style = "Fusion"` for Qt's own) and KDE apps (kdeglobals' fonts and
icons), the font (Google Sans Flex, also fontconfig's default sans-serif) and icons (Adwaita for GTK, Breeze Dark
for Qt and KDE apps), and turns on the
shell's GTK, Qt and KDE color switches. Each part can be left out: `theming.gtk.enable`, `theming.qt.enable`,
`theming.kde.enable`, `theming.fonts.enable` (and `theming.fonts.name`, `.size`; `theming.icons.name`, `.package`
for GTK, `theming.icons.qt.name`, `.package` for Qt and KDE).
Apps pick the colors up when they start.

GTK 4 apps without libadwaita get adw-gtk3 through `GTK_THEME` (`theming.gtk.plainGtk4 = false` leaves them on
GTK's own theme, whose colors are fixed).

This takes over `gtk`, `qt` and `fonts.fontconfig` settings in your home-manager configuration (set them
yourself to override; Nix reports a conflict for a plain value set twice).

## Colors in other apps, with home-manager

Each app has a switch in Settings > Wallpaper (all off at first, and a main one above them). The shell writes the
app's own color file and then adds a line to the app's config so it is used. A config that home-manager manages
is a link into the read-only store: the shell never changes it (that would break your next switch), and says in
its log what to add. Add it in your home-manager configuration instead:

```nix
programs.kitty.extraConfig = "include rutile-colors.conf";
programs.ghostty.settings.theme = "rutile";
programs.btop.settings.color_theme = "rutile";
gtk.gtk3.extraCss = "@import 'rutile.css';";
gtk.gtk4.extraCss = "@import 'rutile.css';";
# qt6ct (and qt5ct likewise), in qt6ct.conf's [Appearance]:
#   color_scheme_path=~/.config/qt6ct/colors/rutile.conf   (written out in full)
#   custom_palette=true
```

With an app's switch off, its file is gone but these lines stay: the app may warn about the missing file until you
remove the line. Neovim needs `:colorscheme rutile` (or `vim.cmd.colorscheme("rutile")` in your init).
Firefox needs the Pywalfox extension; Rutile is its backend. Qt apps follow qt6ct only with
`QT_QPA_PLATFORMTHEME=qt6ct`.

## Things that clash with another shell

One program per session can own each of these; turn them off in the other shell (Noctalia, for example) or the
first one to start keeps them: notifications (`org.freedesktop.Notifications`), the polkit agent (Rutile's:
`programs.rutile.settings.polkit.agent = false` to leave it to the other), the wallpaper, and other apps' colors
(off in Rutile by default).
