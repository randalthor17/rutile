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
- niri's part (`programs.rutile.niri.enable`, on), in a file of its own, `~/.config/niri/rutile.kdl`: a layer
  rule so the power menu and the password dialog blur your windows, not only the wallpaper, the binds if you
  turned them on, and optional includes of the files the shell writes: `rutile-colors.kdl` (niri's colors, while
  Settings > Wallpaper & style > Colors in other apps > niri is on), `rutile-settings.kdl` (Settings > Keyboard,
  mouse & touchpad, and niri's animations at the shell's speed, each while its switch is on) and
  `rutile-display.kdl` (Settings > Display's choices). Rutile's settings win over your own config: the include
  comes last, so its values replace yours, and the shell applies Display's choices again over any `output`
  section of yours whenever it starts or your config changes (D74). niri replaces your whole touchpad and mouse
  sections (and xkb, when a layout is set) with Rutile's while its input switch is on, so your other touchpad and
  mouse settings do not apply then (D75). Your niri config is never changed for you (D72). **Add this line at
  the end of `~/.config/niri/config.kdl` yourself**, so Rutile's settings come after yours and win:

  ```kdl
  include optional=true "rutile.kdl"
  ```

  `optional=true` (niri 26.04 and later) keeps niri's config valid while the file is not there (Rutile not
  installed yet, or `programs.rutile.niri.enable = false`): niri only logs a warning, and picks the file up as
  soon as it appears. A plain `include "rutile.kdl"` makes a missing file an error.

  With home-manager's niri module (`wayland.windowManager.niri`), Rutile can add it for you instead:

  ```nix
  programs.rutile.niri.includeInConfig = true;
  ```

  which puts `include optional=true "~/.config/niri/rutile.kdl"` (the path written out) at the end of the config
  that module generates (D73). Without that module the option stops the switch and says to add the line
  yourself. Until it is there, every home-manager switch prints a reminder, and the shell says so in a
  toast when you turn on a setting that needs it.

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
- Nothing else for Night light: the package brings wlsunset. Turn off any other gamma program (gammastep,
  wlsunset of your own) or Night light stops with a toast saying the gamma is in use.

## GTK, Qt and KDE apps in the shell's look

```nix
programs.rutile.theming.enable = true;
```

sets up GTK (adw-gtk3 for GTK 3 apps and for GTK 4 apps without libadwaita, libadwaita's own theme for the
rest, gtk.css importing the shell's colors; dark or light follows the shell's mode, which it sets itself), Qt (qt5ct and qt6ct with Kvantum and Rutile's
own Kvantum theme, drawn like the GTK apps; `theming.qt.style = "Breeze"` or `"Fusion"` instead) and KDE apps (kdeglobals' fonts and
icons), the font (Google Sans Flex, also fontconfig's default sans-serif) and icons (Papirus-Dark, its folders in
the wallpaper's accent through an icon theme named Rutile; `theming.icons.followWallpaper = false` for plain
Papirus-Dark), and turns on the
shell's GTK, Qt and KDE color switches. Each part can be left out: `theming.gtk.enable`, `theming.qt.enable`,
`theming.kde.enable`, `theming.fonts.enable` (and `theming.fonts.name`, `.size`; `theming.icons.name`, `.package`
for GTK, `theming.icons.qt.name`, `.package` for Qt and KDE).
Apps pick the colors up when they start.

GTK 4 apps without libadwaita get adw-gtk3 through `GTK_THEME` (`theming.gtk.plainGtk4 = false` leaves them on
GTK's own theme, whose colors are fixed).

This takes over `gtk`, `qt` and `fonts.fontconfig` settings in your home-manager configuration (set them
yourself to override; Nix reports a conflict for a plain value set twice).

### Flatpak apps

Flatpak apps see none of this at first: their runtime has its own themes and they cannot read your settings.
Settings > Wallpaper & style > Flatpak apps > Set up… (or `rutile-shell flatpak-theming` in a terminal) installs
adw-gtk3 and Kvantum from Flathub for your user (`flatpak install --user`, after adding Flathub for your user if
needed) and gives every app read-only access to the shell's GTK colors, the Kvantum theme, kdeglobals and
`/nix/store` (where home-manager's links point), with KDE's platform theme for Qt apps
(`flatpak override --user`; `flatpak override --user --show` lists it, `--reset` undoes all user overrides). With
`theming.icons.flatpak` (on by default) home-manager links the icon themes and the font into `~/.local/share`,
where Flatpak apps look. Run it again after installing a Flatpak app on a new KDE runtime. Apps follow the colors
when they start.

### Java apps

Java apps such as Ghidra can show a blank window under niri's xwayland-satellite. `programs.rutile.enable` sets
`_JAVA_AWT_WM_NONREPARENTING=1` for the session (`programs.rutile.javaApps = false` leaves it out); Flatpak apps
get it from `rutile-shell flatpak-theming`. Like every session variable it applies from the next login.

## Colors in other apps, with home-manager

Each app has a switch in Settings > Wallpaper (all off at first, and a main one above them). The shell writes the
app's own color file and then adds a line to the app's config so it is used. A config that home-manager manages
is a link into the read-only store: the shell never changes it (that would break your next switch), and says in
its log what to add. Add it in your home-manager configuration instead:

```nix
programs.kitty.extraConfig = "globinclude themes/Rutile.conf";   # globinclude: no warning while it is off
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

## App indicators

`rutile-shell tray state` shows what the shell sees, each item's icon included; `rutile-shell tray iconPath steam`
where the shell finds an icon by name (its theme is Papirus-Dark; an app's own icon in hicolor is found too).

## Things that clash with another shell

One program per session can own each of these; turn them off in the other shell (Noctalia, for example) or the
first one to start keeps them: notifications (`org.freedesktop.Notifications`), the polkit agent (Rutile's:
`programs.rutile.settings.polkit.agent = false` to leave it to the other), the wallpaper, and other apps' colors
(off in Rutile by default).
