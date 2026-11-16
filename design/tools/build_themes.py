"""Builds the theme catalog.

    python3 -I design/tools/build_themes.py --from-design <project dir>
        Reads the Light and Dark boards on the "Themes" page of the Claude Design canvas (canvas.json and
        its *.dc.html pages, downloaded into <project dir>), converts their CSS values into
        design/themes/themes.json, appends design/themes/legacy.json, then regenerates the Swift embed.

    python3 -I design/tools/build_themes.py
        Regenerates Sources/RingCore/BuiltInThemes.swift from design/themes/themes.json (after a hand edit).

The pages are only read as text: see extract_themes.py.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from extract_themes import page_themes  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
THEMES_JSON = ROOT / "design/themes/themes.json"
LEGACY_JSON = ROOT / "design/themes/legacy.json"
SWIFT_OUT = ROOT / "Sources/RingCore/BuiltInThemes.swift"

# Size in the mock of the box each paint fills, to turn pixel positions into fractions.
BOX = {"disk": 400, "hub": 128, "hubHover": 128}
CANVAS = 720
IDLE = {"xSpin": "spin", "xPulse": "pulse", "xFlicker": "flicker", "xGlitch": "glitch"}


# MARK: - CSS values

def num(x):
    x = round(float(x), 4)
    return int(x) if x == int(x) else x


def split_top(s, sep=","):
    """Splits at `sep` outside parentheses (sep None: any whitespace)."""
    out, depth, cur = [], 0, ""
    for c in s:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and (c == sep or (sep is None and c.isspace())):
            if cur.strip():
                out.append(cur.strip())
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def color(s):
    s = s.strip().lower()
    if s == "transparent":
        return {"r": 0, "g": 0, "b": 0, "a": 0}
    named = {"white": "#ffffff", "black": "#000000"}
    s = named.get(s, s)
    if s.startswith("#"):
        h = s[1:]
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1
        return {"r": num(int(h[0:2], 16) / 255), "g": num(int(h[2:4], 16) / 255),
                "b": num(int(h[4:6], 16) / 255), "a": num(a)}
    m = re.fullmatch(r"rgba?\(([^)]*)\)", s)
    if m:
        parts = [p.strip() for p in m.group(1).split(",")]
        a = float(parts[3]) if len(parts) > 3 else 1
        return {"r": num(float(parts[0]) / 255), "g": num(float(parts[1]) / 255),
                "b": num(float(parts[2]) / 255), "a": num(a)}
    return None


def length(s, box=None):
    """CSS length → our "pt" / "%" / "deg" string. Pixel positions in a box become fractions when `box` is set."""
    s = s.strip()
    if s == "0":
        return "0pt"
    m = re.fullmatch(r"(-?[\d.]+)(px|%|deg)", s)
    if not m:
        raise ValueError(f"bad length {s!r}")
    v, unit = float(m.group(1)), m.group(2)
    if unit == "px":
        return f"{num(v / box * 100)}%" if box else f"{num(v)}pt"
    return f"{num(v)}{'%' if unit == '%' else 'deg'}"


def stops(args):
    out = []
    for arg in args:
        toks = split_top(arg, None)
        c = color(toks[0])
        if c is None:
            raise ValueError(f"bad stop {arg!r}")
        positions = toks[1:] or [None]
        for p in positions:
            out.append({"color": c, **({"at": length(p)} if p else {})})
    return out


def gradient(s, box):
    m = re.match(r"(repeating-)?(linear|radial|conic)-gradient\(", s)
    depth, i = 0, m.end() - 1
    for i in range(m.end() - 1, len(s)):
        depth += {"(": 1, ")": -1}.get(s[i], 0)
        if depth == 0:
            break
    body, rest = s[m.end():i], s[i + 1:].strip()
    repeating, kind = bool(m.group(1)), m.group(2)
    args = split_top(body)
    config = None if color(split_top(args[0], None)[0]) else args.pop(0)
    g = {}
    if kind == "linear":
        g["angle"] = num(config[:-3]) if config and config.endswith("deg") else 180
    elif kind == "radial":
        before, _, after = (config or "").partition("at")
        words = before.split()
        shape = next((w for w in words if w in ("circle", "ellipse")), None)
        sizes = [w for w in words if w not in ("circle", "ellipse")]
        g["shape"] = shape or ("circle" if len(sizes) == 1 else "ellipse")
        if sizes:
            g["size"] = [length(x) for x in sizes]
        g["center"] = [length(x, box) for x in after.split()] if after.strip() else ["50%", "50%"]
    else:
        fm = re.search(r"from\s+(-?[\d.]+)deg", config or "")
        g["from"] = num(fm.group(1)) if fm else 0
        am = re.search(r"at\s+(.*)$", config or "")
        g["center"] = [length(x, box) for x in am.group(1).split()] if am else ["50%", "50%"]
    g["stops"] = stops(args)
    if repeating:
        g["repeating"] = True
    if rest:
        tm = re.fullmatch(r"[^/]*/\s*([\d.]+)px\s+([\d.]+)px", rest)
        if not tm or kind != "radial":
            raise ValueError(f"unsupported background position/size {rest!r}")
        g["tile"] = [num(tm.group(1)), num(tm.group(2))]
    return {kind: g}


def paint(s, key):
    box = BOX.get(key, CANVAS)
    layers = []
    for layer in split_top(s):
        c = color(layer)
        layers.append({"solid": c} if c else gradient(layer, box))
    if len(layers) == 1 and "solid" in layers[0]:
        return layers[0]["solid"]
    return layers


def shadow_list(s):
    out = []
    for part in split_top(s):
        toks = split_top(part, None)
        inset = "inset" in toks
        toks = [t for t in toks if t != "inset"]
        c = next(color(t) for t in toks if color(t))
        nums = [float(t[:-2]) if t.endswith("px") else float(t) for t in toks if not color(t)]
        sh = {"color": c, "x": num(nums[0]), "y": num(nums[1]), "blur": num(nums[2] if len(nums) > 2 else 0)}
        if len(nums) > 3:
            sh["spread"] = num(nums[3])
        if inset:
            sh["inset"] = True
        out.append(sh)
    return out


def declarations(css):
    out = {}
    for d in split_top(css or "", ";"):
        k, _, v = d.partition(":")
        out[k.strip()] = v.strip()
    return out


def idle(animation):
    if not animation:
        return None
    name, period = animation.split()[:2]
    return {"kind": IDLE[name], "period": num(period.rstrip("s"))}


def edge(fx):
    d = declarations(fx)
    e = {}
    if "border" in d:
        w, _, c = d["border"].split(None, 2)
        e["border"] = {"width": num(w[:-2]), "color": color(c)}
    if "box-shadow" in d:
        e["shadows"] = shadow_list(d["box-shadow"])
    return e, idle(d.get("animation"))


def drop_shadows(s):
    if not s or s == "none":
        return None
    return [shadow_list(m)[0] for m in re.findall(r"drop-shadow\(((?:[^()]|\([^()]*\))*)\)", s)]


def font(css):
    if not css:
        return None
    d = declarations(css)
    f = {"family": d["font-family"].split(",")[0].strip().strip("'\""),
         "size": num(d["font-size"].rstrip("px")),
         "weight": int(d.get("font-weight", 400))}
    if d.get("font-style") == "italic":
        f["italic"] = True
    if "letter-spacing" in d:
        f["tracking"] = num(d["letter-spacing"].rstrip("em"))
    if d.get("text-transform") == "uppercase":
        f["uppercase"] = True
    if "text-shadow" in d:
        f["shadows"] = shadow_list(d["text-shadow"])
    return f


# MARK: - Themes

def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def page_description(path, name):
    """The description paragraph under the theme's name, for pages that hard-code it."""
    text = Path(path).read_text()
    m = re.search(r"<h1[^>]*>\s*" + re.escape(name) + r"\s*</h1>\s*<p[^>]*>([^<]+)</p>", text)
    return m.group(1).strip() if m else None


def convert(t, name, dark, family, description):
    disk_edge, disk_idle = edge(t["diskFx"])
    hub_edge, _ = edge(t.get("hubFx", ""))
    rail_colors = [color(t["rail"])]
    if t.get("rail2") and t["rail2"] != t["rail"]:
        rail_colors.append(color(t["rail2"]))
    rail = {"colors": rail_colors, "width": num(t.get("railW", 2.5)), "cap": t.get("railCap", "round")}
    if glow := drop_shadows(t.get("railGlow")):
        rail["glow"] = glow
    if anim := idle(declarations(t.get("railAnim")).get("animation")):
        rail["idle"] = anim
    spec = {
        "id": slug(name), "name": name,
        **({"family": family} if family else {}),
        **({"description": description} if description else {}),
        **({"preview": t["bg"]} if t.get("bg") else {}),
        "backdrop": {"kind": "blur", "dark": dark},
        "disk": paint(t["disk"], "disk"),
        "diskEdge": disk_edge,
        **({"diskIdle": disk_idle} if disk_idle else {}),
        "slice": paint(t["slice"], "slice"),
        "sliceHover": paint(t["sliceHover"], "sliceHover"),
        **({"halo": color(t["halo"])} if t.get("halo") else {}),
        "rail": rail,
        "hub": paint(t["hub"], "hub"),
        "hubEdge": hub_edge,
        "hubHover": paint(t["hubHover"], "hubHover"),
        "text": color(t["text"]), "subtext": color(t["subtext"]),
        "sub": paint(t["sub"], "sub"),
        "subHover": paint(t["subHover"], "subHover"),
        "symbol": color(t["symbol"]), "onHover": color(t["onHover"]),
    }
    if f := font(t.get("hubFontCss")):
        spec["hubFont"] = f
    if f := font(t.get("subFontCss")):
        spec["labelFont"] = f
    return spec


def from_design(project):
    project = Path(project)
    canvas = json.loads((project / "canvas.json").read_text())
    boards = []
    for file, b in canvas["boards"].items():
        m = re.fullmatch(r"(Light|Dark) (\d+) · (.+?)(?: \((\w+)\))?", b.get("title", ""))
        if b.get("page") == "themes" and m:
            boards.append((m.group(1) == "Dark", int(m.group(2)), m.group(3), m.group(4), file))
    themes = []
    for dark, _, name, family, file in sorted(boards):
        variants = page_themes(project / file)
        t = next((v for v in variants.values() if v.get("name", v["_title"].removesuffix(" theme")) == name), None)
        if t is None:
            raise ValueError(f"{file}: no variant named {name}")
        themes.append(convert(t, name, dark, family, t.get("desc") or page_description(project / file, name)))
    return themes


# MARK: - Output

def dump(v, indent=0):
    """JSON with small objects kept on one line."""
    flat = json.dumps(v, ensure_ascii=False)
    if len(flat) + indent <= 110 or not isinstance(v, (dict, list)):
        return flat
    pad = "  " * (indent + 1)
    if isinstance(v, dict):
        items = [f'{pad}{json.dumps(k)}: {dump(x, indent + 1)}' for k, x in v.items()]
        return "{\n" + ",\n".join(items) + "\n" + "  " * indent + "}"
    return "[\n" + ",\n".join(pad + dump(x, indent + 1) for x in v) + "\n" + "  " * indent + "]"


def write_swift(themes):
    SWIFT_OUT.write_text(
        "// Generated by design/tools/build_themes.py from design/themes/themes.json. Don't edit by hand.\n\n"
        "enum BuiltInThemes {\n"
        '    static let json = #"""\n'
        + dump(themes) + "\n"
        '"""#\n'
        "}\n")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--from-design":
        themes = from_design(sys.argv[2]) + json.loads(LEGACY_JSON.read_text())
        THEMES_JSON.write_text(dump(themes) + "\n")
        print(f"Wrote {len(themes)} themes to {THEMES_JSON.relative_to(ROOT)}")
    else:
        themes = json.loads(THEMES_JSON.read_text())
    write_swift(themes)
    print(f"Wrote {SWIFT_OUT.relative_to(ROOT)}")
    print("Check label contrast with: python3 -I design/tools/contrast.py")
