"""Reads the theme object literals out of the Claude Design theme pages (*.dc.html) as plain text.

Nothing from the pages is executed: a small tokenizer reads the JavaScript object literal returned by
`themes()` / `theme()` (strings, numbers, null, booleans, nested objects) and nothing else.
"""
import json
import re
import sys
from pathlib import Path

TOKEN = re.compile(r"""
    \s*(?:
      (?P<str>'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")
    | (?P<num>-?\d+(?:\.\d+)?)
    | (?P<word>[A-Za-z_$][\w$]*)
    | (?P<punct>[{}\[\]:,])
    )""", re.X)


def tokens(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            if text[pos:].strip() == "":
                return
            raise ValueError(f"unexpected input near: {text[pos:pos + 40]!r}")
        pos = m.end()
        kind = m.lastgroup
        yield kind, m.group(kind)


def parse_literal(text):
    """Parses a JS object literal made of plain data."""
    toks = list(tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, tok = toks[i]
        if tok == "{":
            i += 1
            out = {}
            while toks[i][1] != "}":
                k_kind, key = toks[i]
                key = unquote(key) if k_kind == "str" else key
                assert toks[i + 1][1] == ":", f"expected ':' after {key}"
                i += 2
                out[key] = value()
                if toks[i][1] == ",":
                    i += 1
            i += 1
            return out
        if tok == "[":
            i += 1
            out = []
            while toks[i][1] != "]":
                out.append(value())
                if toks[i][1] == ",":
                    i += 1
            i += 1
            return out
        i += 1
        if kind == "str":
            return unquote(tok)
        if kind == "num":
            return float(tok) if "." in tok else int(tok)
        if tok in ("null", "undefined"):
            return None
        if tok in ("true", "false"):
            return tok == "true"
        raise ValueError(f"not plain data: {tok}")

    return value()


def unquote(s):
    return json.loads('"' + s[1:-1].replace('\\"', '"').replace('"', '\\"') + '"') if s[0] == "'" else json.loads(s)


def balanced_object(text, start):
    """The `{...}` starting at `start`, skipping braces inside strings."""
    depth, i, quote = 0, start, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError("unbalanced object")


def page_themes(path):
    """{variant: theme} for a page. Single-theme pages use variant 'a'."""
    text = Path(path).read_text()
    m = re.search(r"\n\s*(themes|theme)\(\)\s*\{\s*return\s*", text)
    if not m:
        return {}
    obj = parse_literal(balanced_object(text, m.end()))
    title = re.search(r"<title>([^<]*)</title>", text).group(1)
    if m.group(1) == "theme":
        obj = {"a": obj}
    for t in obj.values():
        t.setdefault("_title", title)
    return obj


if __name__ == "__main__":
    out = {}
    for p in sys.argv[1:]:
        for vid, t in page_themes(p).items():
            out[f"{Path(p).name}:{vid}"] = t
    json.dump(out, sys.stdout, indent=1)
