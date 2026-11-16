"""Label contrast on hovered sub-actions, around the whole wheel, and the smallest same-hue fix.

    python3 -I design/tools/contrast.py [design/themes/themes.json]


Model (matches the design pages): `subHover` layers are painted over the 720 px wheel box and clipped to
the wedge; the label sits at r 249 from the center. Translucent layers are composited over the
sub-action's resting fill, over a black (dark) or white (light) desktop.
"""
import json, math, sys

themes = {t["id"]: t for t in json.load(open(sys.argv[1] if len(sys.argv) > 1 else "design/themes/themes.json"))}
# The design's wheel area and label radius. The app scales the paint area with its deeper sub-actions
# (ThemeContrast.paintBox), so labels land on the same part of each gradient: the ratios are the same.
BOX, R = 720.0, 249.0

# --- color math -------------------------------------------------------------
def lin(x): return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
def gam(x): return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
def lum(c): return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
def ratio(a, b):
    h, l = max(lum(a), lum(b)), min(lum(a), lum(b)); return (h + .05) / (l + .05)

def to_oklch(c):
    r, g, b = (lin(x) for x in c)
    l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
    m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
    s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b
    l, m, s = (math.copysign(abs(v) ** (1/3), v) for v in (l, m, s))
    L = 0.2104542553*l + 0.7936177850*m - 0.0040720468*s
    A = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
    B = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
    return L, math.hypot(A, B), math.atan2(B, A)

def from_oklch(L, C, H):
    A, B = C * math.cos(H), C * math.sin(H)
    l = (L + 0.3963377774*A + 0.2158037573*B) ** 3
    m = (L - 0.1055613458*A - 0.0638541728*B) ** 3
    s = (L - 0.0894841775*A - 1.2914855480*B) ** 3
    rgb = (4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
           -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
           -0.0041960863*l - 0.7034186147*m + 1.7076147010*s)
    return tuple(gam(x) for x in rgb)

def in_gamut(c): return all(-1e-4 <= x <= 1 + 1e-4 for x in c)

def darker(c, L):
    """Same hue at lightness L, losing as little chroma as needed to stay in sRGB."""
    _, C, H = to_oklch(c)
    while C > 0 and not in_gamut(from_oklch(L, C, H)):
        C -= 0.002
    return tuple(min(max(x, 0), 1) for x in from_oklch(L, C, H))

def hexs(c): return "#" + "".join(f"{round(x * 255):02X}" for x in c[:3])

# --- painting ---------------------------------------------------------------
def rgba(d): return (d["r"], d["g"], d["b"], d.get("a", 1))
def mix(a, b, f): return tuple(a[i] + (b[i] - a[i]) * f for i in range(4))
def over(c, bg): return tuple(c[i] * c[3] + bg[i] * (1 - c[3]) for i in range(3)) + (1,)

def stop_positions(stops, total):
    """Stop offsets in px along a gradient line of length `total` (CSS spreading for missing ones)."""
    pos = []
    for i, s in enumerate(stops):
        at = s.get("at")
        if at is None: pos.append(None)
        elif at.endswith("%"): pos.append(float(at[:-1]) / 100 * total)
        else: pos.append(float(at[:-2]))
    if pos[0] is None: pos[0] = 0
    if pos[-1] is None: pos[-1] = total
    i = 0
    while i < len(pos):
        if pos[i] is None:
            j = i
            while pos[j] is None: j += 1
            for k in range(i, j): pos[k] = pos[i - 1] + (pos[j] - pos[i - 1]) * (k - i + 1) / (j - i + 1)
            i = j
        i += 1
    return pos

def sample(stops, t, total):
    pos = stop_positions(stops, total)
    cols = [rgba(s["color"]) for s in stops]
    if t <= pos[0]: return cols[0]
    for i in range(len(pos) - 1):
        if pos[i] <= t <= pos[i + 1]:
            f = 0 if pos[i + 1] == pos[i] else (t - pos[i]) / (pos[i + 1] - pos[i])
            return mix(cols[i], cols[i + 1], f)
    return cols[-1]

def layer_color(layer, x, y):
    """Color of one layer at (x, y) in the 720 box."""
    if "solid" in layer: return rgba(layer["solid"])
    if "linear" in layer:
        g = layer["linear"]; a = math.radians(g["angle"])
        total = abs(BOX * math.sin(a)) + abs(BOX * math.cos(a))
        t = total / 2 + (x - BOX / 2) * math.sin(a) - (y - BOX / 2) * math.cos(a)
        return sample(g["stops"], t, total)
    if "radial" in layer:
        g = layer["radial"]
        cx, cy = (float(v[:-1]) / 100 * BOX for v in g["center"])
        rx, ry = (float(v[:-1]) / 100 * BOX for v in g["size"])
        t = math.hypot((x - cx) / rx, (y - cy) / ry)  # 1 at the ellipse edge
        return sample(g["stops"], t * rx, rx)
    raise ValueError(layer)

def paint_at(layers, x, y, under):
    c = under
    for layer in reversed(layers):
        c = over(layer_color(layer, x, y), c)
    return c

def layers(p): return p if isinstance(p, list) else [{"solid": p}]

def worst(t, sub_hover):
    desk = (0, 0, 0, 1) if t["backdrop"]["dark"] else (1, 1, 1, 1)
    rest = over(rgba(layers(t["sub"])[-1].get("solid", {"r": 0, "g": 0, "b": 0, "a": 0})), desk)
    on = rgba(t["onHover"])
    out = []
    for deg in range(0, 360, 5):
        a = math.radians(deg)
        x, y = BOX / 2 + R * math.sin(a), BOX / 2 - R * math.cos(a)
        fill = paint_at(sub_hover, x, y, rest)
        out.append((ratio(over(on, fill), fill), deg))
    return min(out)

def place(deg):
    names = ["top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left", "top-left"]
    return names[round(deg / 45) % 8]

def fix(t, target):
    """Darken the base gradient's stops that fail on their own, in equal OKLCH steps, until all positions pass."""
    sh = json.loads(json.dumps(layers(t["subHover"])))
    base = sh[-1]
    kind = next(iter(base))
    stops = base[kind]["stops"] if kind != "solid" else None
    if stops is None: return None
    original = [rgba(s["color"]) for s in stops]
    on = rgba(t["onHover"])
    lowered = [i for i, c in enumerate(original) if ratio(on, c) < target + 0.6]
    for step in range(0, 400):
        for i in lowered:
            L, _, _ = to_oklch(original[i][:3])
            c = darker(original[i][:3], max(L - step * 0.002, 0))
            stops[i]["color"] = {"r": c[0], "g": c[1], "b": c[2], "a": original[i][3]}
        r, _ = worst(t, sh)
        if r >= target:
            return [(hexs(original[i]), hexs(rgba(stops[i]["color"]))) for i in lowered], r
    return None

if __name__ == "__main__":
    print("Worst label contrast on a hovered sub-action (WCAG 2), and the smallest same-hue fix:")
    for t in themes.values():
        r, deg = worst(t, layers(t["subHover"]))
        line = f"  {t['name']:<15} {r:5.2f} at {place(deg):<12}"
        for target in (3.0, 4.5):
            if r < target:
                res = fix(t, target)
                line += f" | {target}:1 " + (", ".join(f"{a}→{b}" for a, b in res[0]) if res else "n/a")
        print(line)
