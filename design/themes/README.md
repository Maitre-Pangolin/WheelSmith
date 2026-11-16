# Theme catalog

`themes.json` holds every built-in theme: the 29 from the Claude Design canvas (page "Themes", 13 light then 16
dark), followed by the two original themes from `legacy.json` (Midnight, Daylight). The app reads it
through `Sources/RingCore/BuiltInThemes.swift`, a generated copy. Don't edit that file by hand.

The format is `ThemeSpec` in `Sources/RingCore/ThemeSpec.swift`. Plain colors are `{"r","g","b","a"}` in 0–1. A paint
that isn't a single color is a list of CSS-like layers, top first: `solid`, `linear`, `radial`, `conic`, optionally
`repeating`, and `tile` for a repeated pattern. Lengths are `"22pt"`, `"55%"` (of the painted box) or `"9deg"`.

## Regenerating

After the designs change on the canvas, download the canvas files (canvas.json and the `*.dc.html` pages) into a folder
and run:

```bash
python3 -I design/tools/build_themes.py --from-design <folder>
```

After editing `themes.json` by hand, run the script without arguments to refresh the Swift copy.

## Contrast

Labels on a hovered sub-action (`onHover` on `subHover`) must reach 3:1 wherever the sub-action sits on the wheel. The
hover paint spans the whole wheel and is clipped to the sub-action, so the color behind a label depends on its
position. `python3 -I design/tools/contrast.py` measures every theme every 5° and suggests the smallest same-hue fix
for any that fall short; `hoveredLabelsHaveContrast` in the tests enforces it.
