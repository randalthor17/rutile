#!/usr/bin/env python3
"""Generate tokens/components.json from the vendored Material 3 component tokens.

Covers button and icon button sizes, shapes, color roles and state opacities.
Everything is parsed from tokens/sources/*.kt (checksummed by manifest.json) and
the script fails loudly on anything it does not understand.

The vendored ButtonXSmallTokens.kt is known to be stale: Compose's own Button.kt
overrides it in code (with TODOs saying the token file is not yet corrected). Those
overrides are applied here as explicit, documented corrections, and the script
checks that the TODOs are still there, so a fix upstream forces a review.

    gen_components.py            write tokens/components.json
    gen_components.py --check    exit 1 if it is stale
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_tokens  # noqa: E402

ROOT = gen_tokens.ROOT
SRC = gen_tokens.SRC
OUT = ROOT / "tokens" / "components.json"

SIZES = {"xs": "XSmall", "s": "Small", "m": "Medium", "l": "Large", "xl": "XLarge"}

# Per type: which token key supplies which role. None means "no such color".
BUTTON_TYPES = {
    "filled": ("FilledButtonTokens.kt", dict(
        container="ContainerColor", content="LabelTextColor", outline=None,
        selected_container="SelectedContainerColor", selected_content="LabelTextSelectedColor",
        unselected_container="UnselectedContainerColor", unselected_content="LabelTextUnselectedColor",
        disabled_container="DisabledContainerColor", disabled_content="DisabledLabelTextColor")),
    "tonal": ("TonalButtonTokens.kt", dict(
        container="ContainerColor", content="LabelTextColor", outline=None,
        selected_container="SelectedContainerColor", selected_content="SelectedLabelTextColor",
        unselected_container="UnselectedContainerColor", unselected_content="UnselectedLabelTextColor",
        disabled_container="DisabledContainerColor", disabled_content="DisabledLabelTextColor")),
    "elevated": ("ElevatedButtonTokens.kt", dict(
        container="ContainerColor", content="LabelTextColor", outline=None,
        selected_container="SelectedContainerColor", selected_content="LabelTextSelectedColor",
        unselected_container="UnselectedContainerColor", unselected_content="LabelTextUnselectedColor",
        disabled_container="DisabledContainerColor", disabled_content="DisabledLabelTextColor")),
    "outlined": ("OutlinedButtonTokens.kt", dict(
        container=None, content="LabelTextColor", outline="OutlineColor",
        selected_container="SelectedContainerColor", selected_content="SelectedLabelTextColor",
        unselected_container=None, unselected_content="UnselectedLabelTextColor",
        disabled_container=None, disabled_content="DisabledLabelTextColor")),
    "text": ("TextButtonTokens.kt", dict(
        container=None, content="LabelColor", outline=None,
        selected_container=None, selected_content=None,
        unselected_container=None, unselected_content=None,
        disabled_container=None, disabled_content="DisabledLabelColor")),
}

ICON_TYPES = {
    "standard": ("IconButtonTokens.kt", dict(
        container=None, content="Color", outline=None,
        selected_container=None, selected_content="SelectedColor",
        unselected_container=None, unselected_content="UnselectedColor",
        disabled_container=None, disabled_content="DisabledColor")),
    "filled": ("FilledIconButtonTokens.kt", dict(
        container="ContainerColor", content="Color", outline=None,
        selected_container="SelectedContainerColor", selected_content="SelectedColor",
        unselected_container="UnselectedContainerColor", unselected_content="UnselectedColor",
        disabled_container="DisabledContainerColor", disabled_content="DisabledColor")),
    "tonal": ("FilledTonalIconButtonTokens.kt", dict(
        container="ContainerColor", content="Color", outline=None,
        selected_container="SelectedContainerColor", selected_content="SelectedColor",
        unselected_container="UnselectedContainerColor", unselected_content="UnselectedColor",
        disabled_container="DisabledContainerColor", disabled_content="DisabledColor")),
    "outlined": ("OutlinedIconButtonTokens.kt", dict(
        container=None, content="Color", outline="OutlineColor",
        selected_container="SelectedContainerColor", selected_content="SelectedColor",
        unselected_container=None, unselected_content="UnselectedColor",
        disabled_container=None, disabled_content="DisabledColor")),
}


class ComponentError(Exception):
    pass


def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def parse_kt(text):
    """name -> raw expression for `inline val X: T get() = expr`, plus `const val X = 0.1f`."""
    out = {n: v.strip() for n, v in re.findall(r"inline val (\w+): [^\n]*\n\s*get\(\) = ([^\n]+)", text)}
    out.update({n: v for n, v in re.findall(r"const val (\w+) = ([\d.]+)f", text)})
    return out


def read(name):
    return parse_kt((SRC / name).read_text())


def dp(expr, what):
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\.dp", expr)
    if not m:
        raise ComponentError(f"{what}: expected dp, got {expr!r}")
    v = float(m.group(1))
    return int(v) if v.is_integer() else v


def shape(expr, corners, what):
    m = re.fullmatch(r"ShapeKeyTokens\.Corner(\w+)", expr)
    if not m:
        raise ComponentError(f"{what}: expected a corner token, got {expr!r}")
    key = snake(m.group(1))
    if key not in corners:
        raise ComponentError(f"{what}: unknown corner {key!r}")
    return "full" if key == "full" else corners[key]


def role(expr, what):
    m = re.fullmatch(r"ColorSchemeKeyTokens\.(\w+)", expr)
    if not m:
        raise ComponentError(f"{what}: expected a color role, got {expr!r}")
    return snake(m.group(1))


def pick(tokens, key, what):
    if key not in tokens:
        raise ComponentError(f"{what}: token {key} not found")
    return tokens[key]


def color_roles(table, file, tokens):
    return {name: (None if key is None else role(pick(tokens, key, file), f"{file}:{key}"))
            for name, key in table.items()}


def button_corrections():
    """Compose overrides the stale XSmall token file in code; verify that is still true."""
    text = (SRC / "Button.kt").read_text()
    pad = re.search(r"val ExtraSmallContentPadding: PaddingValues.*?start = (\d+)\.dp,\s*end = (\d+)\.dp", text, re.S)
    gap = re.search(r"TODO use the value from ButtonXSmallTokens\.kt once it's been corrected\s*"
                    r"public val ExtraSmallIconSpacing: Dp = (\d+)\.dp", text)
    todo = re.search(r"TODO update with the value from ButtonXSmallTokens\.kt once it's been corrected", text)
    if not (pad and gap and todo):
        raise ComponentError(
            "Button.kt no longer overrides the XSmall tokens with the known TODOs: the token file may have "
            "been corrected upstream. Review ButtonXSmallTokens.kt and drop or update the corrections.")
    return {"leading": int(pad.group(1)), "trailing": int(pad.group(2)), "icon_label_gap": int(gap.group(1))}


def label_styles():
    text = (SRC / "Button.kt").read_text()
    m = re.search(r"fun textStyleFor\(buttonHeight: Dp\): TextStyle \{(.*?)\n    \}", text, re.S)
    if not m:
        raise ComponentError("textStyleFor not found in Button.kt")
    body = m.group(1)
    rules = re.findall(r"(buttonHeight < (\w+)Height|else) -> MaterialTheme\.typography\.(\w+)", body)
    want = [("medium", "labelLarge"), ("large", "titleMedium"), ("xLarge", "headlineSmall"), (None, "headlineLarge")]
    got = [(r[1] or None, r[2]) for r in rules]
    if got != want:
        raise ComponentError(f"textStyleFor changed: {got}")
    # buttons shorter than medium (xs, s) -> labelLarge, then m, l, xl
    return {"xs": "label_large", "s": "label_large", "m": "title_medium", "l": "headline_small",
            "xl": "headline_large"}


def build():
    manifest = gen_tokens.load_manifest()
    gen_tokens.verify_sources(manifest)
    corners = json.loads((ROOT / "tokens" / "m3e.json").read_text())["shape"]["corner_dp"]
    state = read("StateTokens.kt")
    filled = read("FilledButtonTokens.kt")

    button_sizes = {}
    styles = label_styles()
    for key, name in SIZES.items():
        f = f"Button{name}Tokens.kt"
        t = read(f)
        button_sizes[key] = {
            "height": dp(pick(t, "ContainerHeight", f), f),
            "icon": dp(pick(t, "IconSize", f), f),
            "icon_label_gap": dp(pick(t, "IconLabelSpace", f), f),
            "leading": dp(pick(t, "LeadingSpace", f), f),
            "trailing": dp(pick(t, "TrailingSpace", f), f),
            "outline": dp(pick(t, "OutlinedOutlineWidth", f), f),
            "shape_round": shape(pick(t, "ContainerShapeRound", f), corners, f),
            "shape_square": shape(pick(t, "ContainerShapeSquare", f), corners, f),
            "shape_pressed": shape(pick(t, "PressedContainerShape", f), corners, f),
            "shape_selected_round": shape(pick(t, "SelectedContainerShapeRound", f), corners, f),
            "shape_selected_square": shape(pick(t, "SelectedContainerShapeSquare", f), corners, f),
            "label_style": styles[key],
        }
    fixes = button_corrections()
    button_sizes["xs"].update(fixes)

    icon_sizes = {}
    for key, name in SIZES.items():
        f = f"{name}IconButtonTokens.kt"
        t = read(f)

        def padding(kind):
            lead = f"{kind}LeadingSpace"
            trail = f"{kind}TrailingSpace"
            if lead not in t:
                return None
            a, b = dp(t[lead], f), dp(t[trail], f)
            if a != b:
                raise ComponentError(f"{f}: asymmetric {kind} padding")
            return a
        default = padding("Default")
        if default is None:
            default = padding("Uniform")
        icon = dp(pick(t, "IconSize", f), f)
        pads = {"default": default, "narrow": padding("Narrow"), "wide": padding("Wide")}
        if None in pads.values():
            raise ComponentError(f"{f}: missing a padding variant {pads}")
        height = dp(pick(t, "ContainerHeight", f), f)
        if icon + 2 * default != height:
            raise ComponentError(f"{f}: default width {icon + 2 * default} is not square ({height})")
        icon_sizes[key] = {
            "height": height,
            "icon": icon,
            "padding": pads,
            "width": {k: icon + 2 * v for k, v in pads.items()},
            "outline": dp(pick(t, "OutlinedOutlineWidth", f), f),
            "shape_round": shape(pick(t, "ContainerShapeRound", f), corners, f),
            "shape_square": shape(pick(t, "ContainerShapeSquare", f), corners, f),
            "shape_pressed": shape(pick(t, "PressedContainerShape", f), corners, f),
            "shape_selected_round": shape(pick(t, "SelectedContainerShapeRound", f), corners, f),
            "shape_selected_square": shape(pick(t, "SelectedContainerShapeSquare", f), corners, f),
        }

    def types(table):
        out = {}
        for tname, (file, keys) in table.items():
            out[tname] = color_roles(keys, file, read(file))
        return out

    btypes, itypes = types(BUTTON_TYPES), types(ICON_TYPES)
    # Types without toggle colors (text button) keep their normal content color when toggled.
    for table in (btypes, itypes):
        for t in table.values():
            for k in ("selected_content", "unselected_content"):
                if t[k] is None:
                    t[k] = t["content"]

    opacity = {
        "hover": num(state, "HoverStateLayerOpacity"),
        "focus": num(state, "FocusStateLayerOpacity"),
        "pressed": num(state, "PressedStateLayerOpacity"),
        "dragged": num(state, "DraggedStateLayerOpacity"),
        "disabled_container": num(filled, "DisabledContainerOpacity"),
        "disabled_content": num(filled, "DisabledLabelTextOpacity"),
    }
    return {
        "_meta": {
            "generator": "tools/gen_components.py",
            "note": "Generated from vendored androidx Compose Material3 token sources (Apache-2.0). "
                    "Do not edit by hand.",
            "corrections": {
                "button.sizes.xs": {
                    "applied": fixes,
                    "reason": "ButtonXSmallTokens.kt is not yet corrected upstream; Compose overrides it in "
                              "Button.kt (ExtraSmallContentPadding, ExtraSmallIconSpacing).",
                },
            },
            "ref": manifest["ref"],
            "fetched": manifest["fetched"],
        },
        "state_opacity": opacity,
        "button": {"sizes": button_sizes, "types": btypes},
        "icon_button": {"sizes": icon_sizes, "types": itypes},
    }


def num(tokens, key):
    v = pick(tokens, key, "tokens")
    f = float(v)
    return int(f) if f.is_integer() else f


def render(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def main(argv):
    try:
        text = render(build())
    except (ComponentError, gen_tokens.TokenError) as e:
        print(f"component error: {e}", file=sys.stderr)
        return 2
    if "--check" in argv:
        if not OUT.exists() or OUT.read_text() != text:
            print("tokens/components.json is stale: run tools/gen_components.py", file=sys.stderr)
            return 1
        print("tokens/components.json is up to date")
        return 0
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
