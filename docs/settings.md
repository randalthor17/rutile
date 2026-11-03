# Settings

How the shell keeps its settings and what it remembers (D45, plan 2.5).

## Files

| Path | Holds | Written by |
|---|---|---|
| `settings/schema.json` (repo) | every setting: type, limits, default, title, description | us |
| `$XDG_CONFIG_HOME/rutile/settings.json` | your settings | the shell (the settings app, IPC), or you |
| `$XDG_CONFIG_HOME/rutile/managed.json` | settings set in Nix | home-manager, read-only |
| `$XDG_STATE_HOME/rutile/state.json` | what the shell remembers: the launcher's view, the desktop's widgets | the shell |
| `$XDG_CACHE_HOME/rutile/palette.json` | the generated palette | matugen |

Without the XDG variables these are `~/.config`, `~/.local/state` and `~/.cache`.

Which value counts, for each setting: `managed.json`, then `settings.json`, then the schema's default. A value
that does not fit the schema (wrong type, out of range) is skipped with a warning in the shell's log, and the
next layer counts. Both settings files are watched, so an edit, or a home-manager switch, applies at once.

The shell writes `settings.json` indented and keeps every key, including ones it does not know. If the file does
not parse, the shell keeps the last good values and changes nothing until it is fixed. It never writes
`managed.json`, and a key set there cannot be changed from the shell.

## The settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `motion.speed` | number, 0 to 4 | 1 | how fast every animation runs (D43): 2 twice as fast, 0 no motion |
| `motion.niri` | true or false | false | niri's own animations at the same speed (0: none), through rutile-settings.kdl (D74) |
| `notifications.sound` | true or false | true | a sound when a notification pops up (pw-play): the sender's, or the sound theme's message sound; none in Do not disturb, except for critical ones |
| `wallpaper.path` | file path | unset | the wallpaper image on every screen, also blurred on the lock screen (unset: a plain surface) |
| `wallpaper.palette` | true or false | true | render the palette from the wallpaper whenever it changes |
| `lock.idleMinutes` | integer, 0 to 240 | 10 | lock after this many minutes without input; 0 never; idle inhibitors (a playing video) hold it off |
| `lock.beforeSleep` | true or false | true | lock when the computer suspends or hibernates |
| `widgets.columns` | 6 to 24 | 12 | square cells across each screen in the desktop widget grid (D81) |
| `widgets.scaleText` | true or false | false | a desktop widget's text and icons follow its size against a new one's 4 x 3 cells, 0.8 to 2 times (D84) |
| `widgets.editor` | a command | unset (xdg-open) | what opens a widget file from the Widgets app; the path goes at the end (D82) |
| `widgets.latitude`, `widgets.longitude` | degrees | unset | where weather widgets report from (D79); a widget can name its own place; without one, no weather is fetched |
| `widgets.units` | metric or imperial | metric | weather in °C and km/h, or °F and mph |
| `widgets.httpAllow` | list of URL beginnings | empty | the addresses widgets may fetch JSON from (`https://host/` and a path start); nothing else is fetched |
| `style.mode` | dark or light | dark | the shell, and the apps that take its colors (GTK's own dark or light too); also Quick Settings' Dark theme tile |
| `style.scheme` | scheme-tonal-spot, -content, -expressive, -fidelity, -fruit-salad, -monochrome, -neutral, -rainbow, -vibrant | scheme-tonal-spot | how the palette is made from its color (Material's scheme types) |
| `style.contrast` | -1 to 1 | 0 | -1 the least, 0 Material's own, 1 the most |
| `style.seed` | #rrggbb | #134aae | the palette's color when there is no wallpaper or colors do not follow it |
| `appColors.enabled` | true or false | false | give other apps the shell's colors (D52); each app below also needs its own switch on |
| `appColors.niri` | true or false | false | niri's focus ring, borders, tab indicators and overview backdrop (a rutile-colors.kdl that niri reads through rutile.kdl, which you include) |
| `appColors.gtk` | true or false | false | GTK 3 and 4 (a rutile.css that gtk.css imports) |
| `appColors.qt` | true or false | false | qt5ct and qt6ct's color scheme |
| `appColors.kde` | true or false | false | KDE apps (Dolphin, Kate) outside Plasma: the colors into kdeglobals, and a Rutile color scheme |
| `appColors.folders` | true or false | false | Papirus's folder icons in the accent: an icon theme, Rutile, on top of Papirus-Dark |
| `appColors.kitty` | true or false | false | a Rutile kitty theme, the 16 terminal colors included; reloads at once |
| `appColors.ghostty` | true or false | false | Ghostty's colors (`theme = rutile`) |
| `appColors.btop` | true or false | false | btop's theme; the previous one comes back when off |
| `appColors.nvim` | true or false | false | a `rutile` colorscheme for Neovim |
| `appColors.firefox` | true or false | false | Firefox through the Pywalfox extension, with Rutile's own host |
| `input.enabled` | true or false | false | apply the input settings below to niri: a rutile-settings.kdl that niri reads through rutile.kdl, which you include at the end of config.kdl (D70, D72) |
| `input.keyboardLayout` | an xkb layout (us, gb, de, fr, ...) or "" | "" | the keyboard's layout; "" leaves niri's config to choose; set, it replaces niri's whole xkb section (variant, options) |
| `input.repeatDelay` | integer, 100 to 1000 | 600 | milliseconds a key is held before it repeats |
| `input.repeatRate` | integer, 5 to 80 | 25 | repeats per second |
| `input.touchpadTap` | true or false | true | tap to click |
| `input.touchpadDisableWhileTyping` | true or false | true | touches do nothing for a moment after a key press (niri's dwt) |
| `input.touchpadNaturalScroll` | true or false | true | content moves with the fingers |
| `input.touchpadSpeed` | -1 to 1 | 0 | touchpad pointer speed (niri's accel-speed) |
| `input.mouseNaturalScroll` | true or false | false | the wheel moves content the other way |
| `input.mouseSpeed` | -1 to 1 | 0 | mouse pointer speed |
| `input.mouseFlat` | true or false | false | no mouse acceleration (niri's flat profile) |
| `nightLight.temperature` | integer, 2500 to 6000 | 4000 | the screen's color temperature in kelvin while Night light is on (Quick Settings; wlsunset, D91) |
| `nightLight.schedule` | true or false | false | warm only from sunset to sunrise (the weather place's sun, `widgets.latitude`/`longitude`), not all day |
| `nightLight.sunset`, `nightLight.sunrise` | "HH:MM" | "19:00", "07:00" | the times used for the schedule while no weather place is set |
| `calendar.feeds` | list of .ics addresses (https://, webcal://) | empty | calendars from the web for the calendar under the clock, e.g. Google Calendar's "Secret address in iCal format"; read only, fetched when it opens, saved in `$XDG_CACHE_HOME/rutile/calendars` for offline use (D94). Secret: keep it out of Nix settings, which land in the world-readable store |
| `calendar.folder` | folder or .ics file | ~/.calendars | where the calendar under the clock reads events: every .ics file in it and the folders right in it (vdirsyncer's layout, one folder per calendar; D93) |
| `windows.enabled` | true or false | false | apply the window settings below to niri, as one window rule after niri's own (rutile-settings.kdl, D88) |
| `windows.floating` | true or false | true | new windows open floating, as on Googlebook, instead of in niri's columns |
| `windows.cornerRadius` | integer, 0 to 32 | 16 | window corners' radius in pixels; windows are clipped to them |
| `windows.shadow` | true or false | true | a soft shadow under every window (niri's own look) |
| `windows.focusRing` | true or false | false | off hides niri's focus ring and border; on leaves them to niri's config |
| `polkit.agent` | true or false | true | be the session's polkit agent (an app asking for an administrator's password asks in the shell); turn off when another agent does it (polkit allows one per session) |
| `shelf.pins` | list of desktop ids | unset | the shelf's pinned apps, in order; unset: the first installed file manager, browser and terminal |

`settings.json` nests the keys:

```json
{
  "motion": { "speed": 1.5 },
  "shelf": { "pins": ["org.gnome.Nautilus", "firefox", "foot"] }
}
```

`RUTILE_ANIMATION_SPEED` overrides `motion.speed` for one run (the tests use it); `ipc call motion setSpeed 2`
saves a new speed and ends the override.

## Home-manager

```nix
{
  imports = [ rutile.homeManagerModules.default ];
  programs.rutile.settings = {
    motion.speed = 1.5;
    shelf.pins = [ "firefox" "foot" ];
  };
}
```

The options are built from `settings/schema.json`, so a wrong type or a value out of range fails at evaluation.
Only the options you set go into `managed.json`; the rest stay the shell's to change. Nothing set, no file.

## Adding a setting

1. Add it to `settings/schema.json`. Supported: objects of `properties`, and leaves of type `boolean`,
   `integer`, `number`, `string`, or `array` of those, with `enum`, `minimum`, `maximum`, `default`, `title`
   and `description`. Names are letters, digits and `_` (they become Nix option names).
2. `make generate` (writes `shell/services/SettingsSchema.js`; `make check` fails on an unsupported schema).
3. Read it with `Settings.value("group.key")` in a binding (it follows changes); change it with
   `Settings.set(key, value)`, which returns false for a managed key or a value the schema refuses.
4. Put it on a page of the settings app: its key in a section of `shell/settingsapp/Pages.js` (a test fails
   while a setting is on no page). Add a hint there when the schema does not say how to show it (`choices`,
   `kind`, `step`, `label`), or to give search more words (`aliases`), or to put it under Advanced.
5. Add it to the table above.

Shell state that is not a setting (usage, the last view) goes through `Settings.stateValue(key, fallback)` and
`Settings.setState(key, value)`, with no schema. It is not configuration and Nix does not touch it.

## State

| Key | Holds |
|---|---|
| `launcher.view` | `"grid"` or `"list"`, as last chosen |
| `launcher.usage` | `{appId: {count, last}}`: apps opened from the launcher, `last` in ms since the epoch; at most 200 apps, the least recently used dropped (`shell/launcher/Usage.js`, D46) |
| `desktop.widgets` | `{output: [{id, path, w, h, col, row}]}`: each screen's desktop widgets, in cells, by output name (D81) |
| `wallpaper.paletteFrom` | the wallpaper the palette was last rendered from, so a restart does not render it again |

Deleting `state.json` forgets all of it; nothing else depends on it.

## Not done

- The settings app (plan 5.1, `shell/settingsapp/`) shows every setting and searches them, and the launcher
  finds them too (D77); the Widgets page is plan 5.2, after the widget system (phase 4).
- A home-manager option that installs the shell: needs the package (plan 6.1).
