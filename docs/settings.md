# Settings

How the shell keeps its settings and what it remembers (D45, plan 2.5).

## Files

| Path | Holds | Written by |
|---|---|---|
| `settings/schema.json` (repo) | every setting: type, limits, default, title, description | us |
| `$XDG_CONFIG_HOME/rutile/settings.json` | your settings | the shell (IPC now, the settings app later), or you |
| `$XDG_CONFIG_HOME/rutile/managed.json` | settings set in Nix | home-manager, read-only |
| `$XDG_STATE_HOME/rutile/state.json` | what the shell remembers: the launcher's view | the shell |
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
| `notifications.sound` | true or false | true | a sound when a notification pops up (pw-play): the sender's, or the sound theme's message sound; none in Do not disturb, except for critical ones |
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
4. Add it to the table above.

Shell state that is not a setting (usage, the last view) goes through `Settings.stateValue(key, fallback)` and
`Settings.setState(key, value)`, with no schema. It is not configuration and Nix does not touch it.

## State

| Key | Holds |
|---|---|
| `launcher.view` | `"grid"` or `"list"`, as last chosen |
| `launcher.usage` | `{appId: {count, last}}`: apps opened from the launcher, `last` in ms since the epoch; at most 200 apps, the least recently used dropped (`shell/launcher/Usage.js`, D46) |

Deleting `state.json` forgets all of it; nothing else depends on it.

## Not done

- The registry's search fields (icon, aliases, children, advanced/hidden) and settings search: with the settings
  app (plan 5.1).
- A home-manager option that installs the shell: needs the package (plan 6.1).
