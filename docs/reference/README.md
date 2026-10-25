# References

Screenshots of Googlebook (supplied by the maintainer, October 2026) that Rutile is compared against. They are
references for look and layout only; nothing is traced or copied from them. Pixel sizes below are estimates
from the screenshots (most are scaled), so the vendored Android and Compose sources stay the source of exact
values (D32).

| File | Shows |
|---|---|
| `googlebook-top-tiles.jpg` | Quick Settings over Settings, lavender (wallpaper-derived) dark scheme |
| `googlebook-panel-right-with-some-widgets.webp` | Quick Settings with active tiles, blue scheme, desktop widgets |
| `googlebook-panel-right-with-edit-mode.webp` | Quick Settings edit mode ("Edit tiles") |
| `googlebook-full-desktop.jpg` | Desktop: widgets, right-hand icon column, status pills, shelf |
| `googlebook-settings-1.jpg` | Settings: single-choice dialog ("Choose modifier key") |
| `googlebook-settings-2.jpg` | Settings: home list and a sub-page list |
| `googlebook-settings-3.jpg` | Settings: radio-button dialog ("Customize corner shortcuts") |

## What they show, per part

Quick Settings panel (plan 2.6):

- A floating panel under the status pills, about 28 px corners, on a surface container tinted by the scheme.
- Header row: edit-tiles and settings icon buttons on the left, a power button with a chevron on the right.
- Brightness and volume: thick expressive sliders (about 40 px) with the icon inside the inactive track end,
  each followed by an icon button (dark theme, sound settings). Rutile's Slider has only the standard size so far.
- Tiles are Android 16's (D32): 4 columns; large tiles span 2 and small tiles are icon-only. Inactive tiles are
  pills; active ones are rounded squares filled with the primary color; a dual-target tile (Wi-Fi, Bluetooth)
  keeps a surface body and a primary icon box when on, and a slightly lighter round icon box when off.
- Unlabelled small tiles show no secondary text; large tiles show a state line ("Available", "Until bedtime").

Quick Settings edit mode (plans 1.6 and 2.6):

- The panel turns into "Edit tiles": a back arrow, the title, and a filled "Remove" button.
- The current tiles sit in a container with a primary outline. The selected tile gets a primary outline and a
  resize handle on its right edge (a short vertical bar) to switch between small and large.
- Below, the available tiles are grouped by category (Connectivity, Utilities, Display) with a category icon:
  each is a round icon with its label underneath and a "+" badge; tiles already added are shown faded.

Settings (plans 2.5 and 5.x):

- Segmented lists: a group's first and last items have large outer corners, inner corners are small, items
  are about 2 px apart. This is Rutile's ListItem `position`.
- Home list: each item has a 40 to 48 px circular icon in its own category color, a title and a summary. The
  selected page in the sidebar is a lighter container.
- Search field: a full-height pill with an outline on the darkest surface.
- Dialogs: about 28 px corners; a single-choice list with the selected row as a filled pill and a check; or
  radio buttons; an outlined Cancel and a filled Done.

Desktop (plans 2.3 and 4.x):

- Widgets are cards with large corners (about 28 px) on a tinted container; inner rows (calendar events,
  scores) are smaller rounded rows on a darker or tonal fill.
- A column of desktop icons on the right: tonal circles with a label underneath.
- Top right: a media pill, notification and do-not-disturb icons, and a status pill (Wi-Fi, battery).
- The shelf: a "G" pill, pinned apps with running dots, a divider, the assistant button.

Color: the scheme follows the wallpaper (lavender in one capture, blue in the others), as matugen does; the
default seed is still open (plan 1.1b).
