# WheelSmith: hovered-label contrast fixes for Claude Design

Paste this into Claude Design on the **WheelSmith Themes** canvas.

## The problem

When a sub-action is hovered, its label and icon (`onHover`) sit on the hover fill (`subHover`). In four themes that
label is hard to read in some places around the wheel:

| Theme | Worst contrast now | Where | Why |
|---|---|---|---|
| Plasma | 2.1 : 1 | bottom-right | White on the light end of indigo `#818CF8` → cyan `#22D3EE`; both ends are light |
| Pearl | 1.9 : 1 | top | White on light pink `#EF8FB3`, plus the white gloss highlight across the top |
| Glacier | 2.5 : 1 | top | White on the light-cyan end `#38BDF8` |
| Sunfire | 2.6 : 1 | top | White on the orange end `#FF8A00` |

Every other theme is at 3 : 1 or better everywhere.

How it's measured: the hover gradient is painted across the whole wheel (the 720 px box) and clipped to the hovered
sub-action, as on the theme boards today. **Keep it that way.** So the color behind a label depends on where the
sub-action sits: Sunfire's top sub-actions get the orange end, its bottom ones the red end. The label sits 249 px
from the center. Contrast is the WCAG 2 ratio, checked every 5° around the wheel, with translucent layers composited
over the resting sub-action and a black (dark theme) or white (light theme) desktop.

WCAG 2 is known to under-rate white on saturated orange and cyan, so Sunfire and Glacier may look better than their
numbers. Judge them by eye too.

## Target

- **At least 3 : 1 at every position** for the label on the hovered sub-action (WCAG's level for large text and UI).
- **Keep each theme's personality:** same hues, same wheel-wide gradient, same direction. Prefer darkening the light
  end of the gradient (same hue, lower lightness) or softening overlays over changing colors.
- Don't touch the other tokens unless a fix needs it.

## Starting points (computed, same hue in OKLCH, smallest change that reaches 3 : 1)

| Theme | Change |
|---|---|
| Sunfire | `#FF8A00` → `#EB7F07` (barely visible) |
| Glacier | `#38BDF8` → `#13A9E3` |
| Plasma | `#818CF8` → `#656ED6` and `#22D3EE` → `#0EB1C9` |
| Pearl | Soften the top highlight from white 0.7 to about 0.2, **and** `#EF8FB3` → `#D4779B`. With the highlight left as is, the pink has to go all the way to `#A0486C`, which loses the pearl look. A dark plum label is another route, but the deep end of the gradient (`#C2185B`) would then be too dark for it. Pick what keeps Pearl feeling like Pearl. |

For reference, 4.5 : 1 everywhere would take much bigger shifts (Sunfire `#E8340C` → `#A31F01` and `#FF8A00` →
`#C06706`; Glacier `#38BDF8` → `#0583B2`), plus small darkening in twelve more themes. Not asked for now.

## What I'd like back

1. A new page, **Contrast**, with a **before and after** board for each of the four themes, side by side, built from
   the existing theme board. On each pair, start with the sub-action hovered at the worst position from the table
   (for example Dia › Search at the top for Sunfire, Glacier and Pearl), so the difference shows without hovering.
   Under the "after" board, list the exact changed values.
2. Once a fix looks right, **apply it to that theme's board on the Themes page** as well, keeping the board titles
   ("Light 04 · Sunfire (fire)" etc.). The app's converter reads the Themes page, so that's where the final values
   must end up.
