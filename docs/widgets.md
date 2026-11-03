# Writing widgets

A desktop widget is a JSON file: a tree of building blocks, with `{{source.field}}` where live data goes. There is
no code in it. The shell draws it in the wallpaper's colors (D18, D78).

## Quick start

1. Open **Rutile Widgets** from the app launcher (or `rutile-shell widgets gallery`), pick a template, and press
   **Use**. It is copied to `~/.config/rutile/widgets/` and put on the desktop.
2. Under **Your widgets**, press **Edit**: the file opens in your editor beside a live preview. Settings > Widgets >
   "Open widget files with" picks the editor, e.g. `neovide` or `kitty -e nvim` (`xdg-open` when unset, which may
   pick a browser for JSON).
3. Edit and save. The preview and the desktop show the change at once, and the preview lists what is wrong.
4. From a terminal:

```
rutile-shell widgets preview my-widget.json            # a window with it, live, redrawn on save
rutile-shell widgets check my-widget.json              # its problems, one per line; exit 1 if any
rutile-shell widgets check my-widget.json --json       # {"ok": ..., "problems": [{"path", "message"}]}
rutile-shell widgets install my-widget.json --place    # check, copy to ~/.config/rutile/widgets, put on the desktop
```

`check` and `install` ask the running shell, so it must be running.

## A widget

```json
{
  "version": 1,
  "name": "Battery",
  "root": {
    "type": "card",
    "tone": "primary_container",
    "children": [
      { "type": "header", "icon": "battery_full", "title": "Battery" },
      { "type": "stat", "label": "Level", "value": "{{battery.level}}", "unit": "%" },
      { "type": "progress", "value": "{{battery.fraction}}" }
    ]
  }
}
```

`version` is 1, `name` is what the Widgets app and the desktop's Add menu show, and `root` is one block.
`widgets/spec.schema.json` is the full spec; `widgets/examples/` and `widgets/templates/` have 35 working widgets.

## Blocks

| Type | Fields | Draws |
|---|---|---|
| `card` | `children`, `tone` | a rounded surface (surface_container unless `tone` says) |
| `tile` | `children`, `tone` (required) | a smaller tinted block |
| `column` | `children`, `spacing` | children stacked |
| `row` | `children`, `spacing` | children side by side, sharing the width; chips keep their own |
| `grid` | `children`, `columns` (1 to 6), `spacing` | children in columns |
| `header` | `title`, `icon` | a title with an icon |
| `stat` | `value`, `label`, `unit` | a big value |
| `progress` | `value` (0 to 1 or a binding), `style` (`linear`, `wavy`) | a progress bar |
| `listRow` | `title`, `subtitle`, `icon`, `trailingIcon` | a list row; binding into a list repeats it (up to 8) |
| `chip` | `label`, `icon` | a small outlined label |
| `chart` | `kind`, then `values`, `series` or `value`; `min`, `max`, `points`, `label`, `unit`, `tone`, `size` | a chart (below) |
| `heroImage` | `source` (path, URL or binding), `aspect` (`16:9`) | a picture |

- `tone` is a surface color role: `primary_container`, `secondary_container`, `tertiary_container`,
  `surface_container_high`, `error_container` and others (the schema lists them all). Text on it takes the matching
  color.
- `icon` is a [Material Symbols](https://fonts.google.com/icons) name, such as `partly_cloudy_day` or `timer`.
- `spacing` is a size name: `none`, `xs`, `sm`, `md`, `lg`, `xl`, `xxl` or `xxxl`.

## Live data

Write `{{source.field}}` in any text. A missing value shows as a dash.

| Source | Fields | Options (`"sources": {...}` in the widget) |
|---|---|---|
| `clock` | time, seconds, date, weekday, day, month, year, hour, minute, dayProgress | `utcOffset` (hours, for another place's time) |
| `battery` | present, level, fraction, charging, status, timeLeft | |
| `system` | cpu, cpuFraction, memory, memoryFraction, memoryUsed, memoryTotal, uptime, load | |
| `countdown` | days, hours, minutes, text, done, remaining, progress | `target` (required, `2026-12-25` or `2026-12-25T18:00`), `from` |
| `media` | playing, title, artist, album, art, progress, player | |
| `weather` | temperature, apparent, high, low, unit, humidity, wind, condition, symbol | `latitude`, `longitude`, `units`; Settings > Widgets otherwise |
| `calendar` | events (a list: title, date, time, when), next, nextWhen, count | `path` (required: an .ics file, or a folder and the folders right in it), `days`; repeating events at each time (D93) |
| `files` | text, firstLine, lines (a list: text), json (the file's own fields) | `path` (required) |
| `http` | the document's own fields, e.g. `{{http.rates.EUR}}` | `url` (required), `every` (seconds, at least 60) |

| `system` (more) | cpuName, cores (numbers), cpuFrequency, cpuHistory, memoryUsedGB, memoryFreeGB, memoryHistory, swap, swapUsed, swapTotal, disk, diskUsed, diskFree, diskTotal, diskUsedGB, diskFreeGB, download, upload, downloadRate, uploadRate, downloadHistory, uploadHistory | `every` (seconds, 1 when missing), `history` (samples, 60) |
| `gpu` | available, name, usage, usageHistory, vram, vramUsed, vramTotal, vramUsedGB, vramFreeGB, temperature, temperatureHistory, hotspot, memoryTemperature, power, powerHistory, fan, clock | `card` (`card1`, `nvidia0`; the one with the most video memory when missing), `every`, `history` |
| `sensors` | cpu, cpuHistory, nvme, hottest, temperatures (a list: name, value), cpuPower (RAPL; usually needs root) | `every`, `history` |

`widgets/sources.json` describes every field. A field the hardware does not report (a GPU without a hotspot sensor)
shows a dash. A web address is fetched only when Settings > Widgets > "Web data
widgets may read" allows it (the Widgets app's Use allows a template's own).

```json
"sources": { "http": { "url": "https://api.frankfurter.dev/v1/latest?from=USD", "every": 3600 } }
```

## Charts

```json
{ "type": "chart", "kind": "area", "values": "{{system.cpuHistory}}", "label": "CPU", "unit": "%", "max": 100 }
{ "type": "chart", "kind": "gauge", "value": "{{gpu.usage}}", "unit": "%", "label": "GPU", "size": "small" }
{ "type": "chart", "kind": "donut", "label": "RAM", "unit": "GB", "series": [
    { "label": "Used", "value": "{{system.memoryUsedGB}}" },
    { "label": "Free", "value": "{{system.memoryFreeGB}}", "tone": "surface_variant" } ] }
{ "type": "chart", "kind": "bar", "values": "{{system.cores}}", "max": 100 }
```

| Kind | Data | Draws |
|---|---|---|
| `line`, `area` | `values`: a history (`{{system.cpuHistory}}`) or a list of numbers; or `series` of histories, one line each | a line over time; the newest at the right, `points` samples across (60 when missing: a minute) |
| `bar` | `values` (one bar each) or `series` (labelled bars) | bars from `min` |
| `pie`, `donut` | `series`: `[{ "label", "value", "tone" }]` | slices with a legend; a donut shows `label` in its middle |
| `gauge` | `value` | three quarters of a ring, from `min` (0) to `max` (100) |

`min` is 0 and `max` the largest value unless given. `size` is `small`, `medium` (default) or `large`. `tone` colors a
line, bars or a gauge; series take primary, tertiary, secondary and error in turn unless they name a tone (on a
tinted card or tile, its text color, fading).

## On the desktop

Right-click a widget, or the desktop and choose "Edit widgets", to move, resize, add and remove them. While you
edit, every screen switches to its empty workspace so the apps are out of the way (niri has no minimize); Done
switches back. A widget made bigger
stretches its cards and tiles to fill the space; one without a card is centered in it with a margin. Settings >
Widgets > "Scale text with widget size" also makes text bigger in a bigger widget (off by default). A widget taller
than its space is shrunk to fit.
