# WheelSmith: theme & motion brief for Claude Design

Paste this brief into Claude Design and attach the PNGs from `screens/`.

## What the app is

WheelSmith is a macOS radial quick-action wheel. You hold a hotkey and the wheel appears centered on the
pointer. You move toward a slice and release to trigger it (launch an app, run an action, pick a window).
The wheel floats over **whatever is on screen**, any wallpaper or app, with a blurred or Liquid Glass
backdrop behind it. It's on screen for under a second at a time, so it must read instantly.

## Anatomy (all sizes in points, measured from the center)

| Part | Geometry | Notes |
|---|---|---|
| Hub | circle, radius 44 | Shows the hovered item's app + action name. Empty while the pointer rests there during the first second (letting go just closes the wheel). After 1 s it **arms**: a ⚙ "Settings" label fades in, the fill switches to `hubHover` and the outline to the `sliceHover` gradient, and letting go opens Settings. |
| Slice ring | radius 52 → 148, up to 10 slices (10 by default) | App icon per slice. A small dot on the outer edge means the slice has sub-actions. |
| Sub-ring | radius 156 → 236, 34° per child | Fans out around the hovered slice when it has children. SF Symbol icon + label. |
| Canvas | 528 × 528 | Transparent outside the wheel. |

Reference screenshots (rendered over a solid gradient, because blur can't be captured offscreen):

- `wheel-midnight-center.png`: at rest, pointer on the hub (first second: nothing armed)
- `wheel-midnight-settings.png`: pointer on the hub after 1 s, Settings armed
- `wheel-midnight-slice.png`: one slice hovered
- `wheel-midnight-sub.png`: sub-ring open, a child hovered
- `wheel-daylight-sub.png`: the light theme
- `wheel-glass-slice.png`: the Liquid Glass theme
- `wheel-glass-sub.png`: Liquid Glass with a sub-action hovered (near-white pane, dark label)
- `wheel-windows.png`: the window picker (sub-ring listing an app's windows)
- `wheel-prompt-*.png`: a Prompt action, where the wheel stays open with a text field beside it

## Color tokens

Every color the wheel uses is one of these. A theme is just a set of values for them.

| Token | Paints | Midnight (current) |
|---|---|---|
| `backdrop` | Material behind the wheel: `blur` or `glass`, plus `dark: true/false` | blur (HUD), dark |
| `disk` | Tint laid over the backdrop, filling the slice ring | rgb(0.04, 0.04, 0.08) @ 0.62 |
| `stroke` | Separator lines between slices and around rings | white @ 0.10 |
| `slice` | A slice at rest | white @ 0.045 |
| `sliceHover` | Hovered slice / child: a 2-stop gradient | rgb(0.49, 0.36, 1.0) → rgb(0.18, 0.62, 1.0) |
| `glow` | Halo around the selected slice (blur radius 16, 0.65 opacity) | rgb(0.36, 0.48, 1.0) |
| `hub` | Center circle | rgb(0.09, 0.09, 0.13) @ 0.92 |
| `hubHover` | Center circle while Settings is armed and the pointer is on it | rgb(0.16, 0.15, 0.24) |
| `text` | Primary labels (hub title, child labels) | white |
| `subtext` | Secondary labels (app name above the hub title) | white @ 0.55 |
| `sub` | Fill of a sub-ring child at rest | rgb(0.07, 0.07, 0.11) @ 0.94 |
| `symbol` | SF Symbol icons | white @ 0.92 |
| `onHover` | Labels, symbols and the sub-action dot drawn **on top of `sliceHover`** | white |
| `shadow` | Drop shadow under the wheel | black @ 0.45 |

The other two existing themes, for reference:

- **Daylight**: light blur. Disk white @ 0.55, hover gradient warm orange → pink, rgb(1.0, 0.52, 0.30) → rgb(1.0, 0.30, 0.45),
  near-black text.
- **Liquid Glass**: macOS 26 glass. Very low tints (disk black @ 0.18), white glow @ 0.7. Each sub-action
  is its own pane of glass. Hover is near-opaque white (0.92 → 0.78) with near-black `onHover` labels.
  It used to be white @ 0.42 → 0.22 with white labels, and the hovered sub-action vanished over light
  desktops, so keep this case in mind for any translucent theme.

## Motion (current values, SwiftUI springs)

| Token | What it animates | Current |
|---|---|---|
| `appear` | Wheel fades in when the hotkey is pressed | spring(response 0.24, damping 0.80), opacity 0 → 1 |
| `hover` | Hover moving between slices / children | spring(response 0.22, damping 0.78) |
| `subAppear` | Sub-ring children appearing | scale 0.86 → 1 + fade, same spring as hover |
| `glowRadius` | Selected-slice halo | 16 |
| `settingsArm` | Hub's ⚙ Settings label appearing after 1 s on the center | ease-out 0.18 s, fade + scale 0.8 → 1 |

Constraints on motion:

- The wheel is used dozens of times a day, for under a second each time. Motion must feel **fast and
  confirming**, never decorative or slow. Anything over ~250 ms will feel laggy.
- Every motion needs a **Reduce Motion** fallback (a short opacity fade only).
- The motion will be rebuilt as SwiftUI springs (`response` in seconds, `dampingFraction` 0–1). Describe
  motion in those terms, or as a CSS spring that can be translated into them.

## Constraints

- Must stay legible over **any** wallpaper: bright photos, dark desktops, busy app windows.
- `onHover` must stay readable **on top of `sliceHover`**, over any wallpaper (that's where the hovered
  label sits). A translucent `sliceHover` needs enough alpha to stay visible over both dark and light
  desktops.
- App icons are full-color, so the ring itself shouldn't fight them for attention.
- Each theme declares whether it's dark or light. A theme only has to work in its own mode.
- Colors are RGB in **0–1** plus an alpha. No hex, no named colors.

## What I'd like back

1. An **interactive mock** of the wheel (hub, 10 slices, a sub-ring with 3 children) where I can hover slices
   and switch between themes, over a few different backgrounds (dark wallpaper, bright photo, white window).
   Include the hub's armed Settings state (after 1 s on the center).
2. **4–6 new theme proposals** with distinct personalities: e.g. a calm one, a neon one, a warm one, a
   high-contrast one, a monochrome one. Include at least one light theme.
3. One or two **motion ideas** that go beyond the current springs (e.g. a staggered slice reveal, a glow
   that pulses once on selection, a sub-ring that unfolds from its parent slice). Also how the hub should
   signal that Settings has armed: today the ⚙ label simply fades in, which is easy to miss. For each:
   duration, and how it degrades under Reduce Motion.
4. Each theme's values as **JSON in exactly this shape**, so they map one-to-one onto the Swift `Theme` struct:

```json
{
  "id": "ember",
  "name": "Ember",
  "backdrop": { "kind": "blur", "dark": true },
  "disk":       { "r": 0.08, "g": 0.04, "b": 0.03, "a": 0.62 },
  "stroke":     { "r": 1, "g": 1, "b": 1, "a": 0.10 },
  "slice":      { "r": 1, "g": 1, "b": 1, "a": 0.045 },
  "sliceHover": [ { "r": 1.0, "g": 0.45, "b": 0.20, "a": 1 },
                  { "r": 1.0, "g": 0.20, "b": 0.35, "a": 1 } ],
  "glow":       { "r": 1.0, "g": 0.40, "b": 0.30, "a": 1 },
  "hub":        { "r": 0.10, "g": 0.06, "b": 0.05, "a": 0.92 },
  "hubHover":   { "r": 0.18, "g": 0.10, "b": 0.08, "a": 1 },
  "text":       { "r": 1, "g": 1, "b": 1, "a": 1 },
  "subtext":    { "r": 1, "g": 1, "b": 1, "a": 0.55 },
  "sub":        { "r": 0.09, "g": 0.05, "b": 0.04, "a": 0.94 },
  "symbol":     { "r": 1, "g": 1, "b": 1, "a": 0.92 },
  "onHover":    { "r": 1, "g": 1, "b": 1, "a": 1 },
  "shadow":     { "r": 0, "g": 0, "b": 0, "a": 0.45 },
  "motion": {
    "appearResponse": 0.24, "appearDamping": 0.80,
    "hoverResponse": 0.22,  "hoverDamping": 0.78,
    "subAppearScale": 0.86, "glowRadius": 16
  }
}
```

`backdrop.kind` is `"blur"` or `"glass"`.
