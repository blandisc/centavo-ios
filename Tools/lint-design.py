#!/usr/bin/env python3
"""Design-system lint for Centavo («Noche ticket»).

Fails (exit 1) when a view writes a value that must come from the design system:
numbers in layout modifiers, fixed font sizes, literal or system colors, hand-made
prominent buttons, aggressive minimumScaleFactor… See docs/DESIGN_SYSTEM.md.

Usage: Tools/lint-design.sh [--quiet] [--summary] [files…]
(no files = every .swift under Centavo/Screens, Centavo/Components, Centavo/App and CentavoWidgets)

Per-line exception: end the line with `// ds-allow: <why>`. The reason is required; every
exception is counted and listed at the end, so they stay visible in review.
Standard library only (runs on macOS and Linux, no dependencies).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Centavo"

# The code that draws views. Model/, Intents/ and the rest hold no layout.
UI_DIRS = [APP / "Screens", APP / "Components", APP / "App", ROOT / "CentavoWidgets"]

# Where the tokens are defined: the only place allowed to write the raw values.
TOKEN_DIRS = [APP / "Theme"]

# Files that draw Apple's Shortcuts app on purpose (the setup guide). They copy another
# app's measurements and type, so layout and font rules don't apply; colors still do
# (they must use Theme.Shortcuts).
DRAWINGS = {
    APP / "Screens" / "ShortcutsDrawing.swift",
    APP / "Screens" / "GuideFrames.swift",
}

NUM = r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w])"

# Modifiers / labels whose argument must be a token, never a number.
NUMERIC_ARGS = [
    "padding", "spacing", "cornerRadius", "presentationCornerRadius", "lineWidth", "frame",
    "opacity", "offset", "tracking", "kerning", "minimumScaleFactor", "lineSpacing",
    "scaleEffect", "blur", "shadow", "dash", "duration", "delay", "bounce", "minimum",
    "maximum", "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
    "idealWidth", "idealHeight", "radius",
]
ARG_RE = re.compile(r"(?<![\w])(?:\.)?(" + "|".join(NUMERIC_ARGS) + r")\s*([(:])")

COLOR_NAMES = ("red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|"
               "white|black|gray|grey|primary|secondary|accentColor")

RULES = [
    # (id, regex, message, applies to drawings)
    ("font-system-size", re.compile(r"\.font\(\s*\.system\("),
     "tamaño de fuente fijo: usa .font(.ticket(.rol)) (TicketStyle)", False),
    ("font-ticket-size", re.compile(r"\.ticket\(\s*-?\d"),
     "tamaño de letra con número: usa un rol de TicketStyle, p. ej. .ticket(.body)", False),
    ("font-system-style", re.compile(
        r"\.font\(\s*\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|"
        r"footnote|caption|caption2)\b"),
     "estilo de texto del sistema: el texto usa .ticket(.rol); los símbolos, Theme.Symbol", False),
    ("color-literal", re.compile(
        r"\b(Color|UIColor)\(\s*(red|hex|white|\.sRGB|\.displayP3|hue|uiColor|cgColor)\b|"
        r"#colorLiteral|0x[0-9A-Fa-f]{6}\b"),
     "color literal: usa un color de Theme", True),
    ("color-system", re.compile(
        r"(?:\bColor\.|(?:foregroundStyle|foregroundColor|tint|fill|stroke|background|"
        r"strokeBorder)\(\s*\.)(" + COLOR_NAMES + r")\b"),
     "color del sistema: usa un color de Theme (el modo oscuro es forzado)", True),
    ("hand-made-prominent", re.compile(r"\.buttonStyle\(\s*\.(borderedProminent|glassProminent)"),
     "botón prominente a mano: usa .ticketProminent()", False),
    ("system-bordered", re.compile(r"\.buttonStyle\(\s*\.(bordered|glass)\s*\)"),
     "botón gris del sistema: usa TicketChip (sugerencias) o SecondaryButton", False),
    ("color-scheme", re.compile(r"\.preferredColorScheme\("),
     "esquema de color a mano: la app ya fuerza el oscuro; en #Preview usa .ticketPreview()",
     False),
    ("scaled-metric-number", re.compile(r"@ScaledMetric[^=]*=\s*-?\d"),
     "@ScaledMetric con número: usa un valor de Theme.Size como base", False),
]

# Files outside Theme/ allowed to use a rule, and why.
RULE_EXEMPT = {
    "color-scheme": {APP / "App" / "CentavoApp.swift", APP / "Components" / "Preview.swift"},
    "hand-made-prominent": {APP / "Components" / "Buttons.swift"},
}

ALLOW_RE = re.compile(r"//\s*ds-allow\b:?\s*(.*)$")


def strip_comment(line: str) -> str:
    """Drops a trailing // comment that is not inside a string literal."""
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_str:
            i += 2
            continue
        if c == '"':
            in_str = not in_str
        elif not in_str and line.startswith("//", i):
            return line[:i]
        i += 1
    return line


def strip_strings(line: str) -> str:
    """Blanks string literals so numbers inside text («Cada 2 semanas») don't count."""
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', line)


def arg_span(code: str, start: int, opener: str) -> str:
    """The argument text after `name(` (balanced) or `name:` (up to , or ) at depth 0)."""
    depth = 1 if opener == "(" else 0
    out = []
    i = start
    while i < len(code):
        c = code[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
            if depth < 0 or (opener == "(" and depth == 0):
                break
        elif c == "," and depth == 0 and opener == ":":
            break
        out.append(c)
        i += 1
    return "".join(out)


def numeric_violation(code: str):
    for m in ARG_RE.finditer(code):
        name, opener = m.group(1), m.group(2)
        span = arg_span(code, m.end(), opener)
        # `.infinity`, tokens and expressions without literals are fine.
        if re.search(NUM, span):
            return name
    return None


def lint_file(path: Path):
    problems, allows = [], []
    drawing = path in DRAWINGS
    lines = path.read_text(encoding="utf-8").splitlines()
    in_block_comment = False
    for n, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            continue
        if stripped.startswith("/*"):
            in_block_comment = "*/" not in stripped
            continue
        if stripped.startswith("//"):
            continue
        allow = ALLOW_RE.search(raw)
        code = strip_strings(strip_comment(raw))
        found = []
        for rule_id, regex, message, on_drawings in RULES:
            if drawing and not on_drawings:
                continue
            if path in RULE_EXEMPT.get(rule_id, ()):
                continue
            if regex.search(code):
                found.append((rule_id, message))
        if not drawing:
            name = numeric_violation(code)
            if name:
                found.append(("magic-number",
                              f"número suelto en `{name}`: usa Theme.Space/Radius/Size/Stroke/"
                              "Opacity/Tracking/MinimumScale/Motion"))
        if not found:
            continue
        rel = path.relative_to(ROOT)
        if allow:
            reason = allow.group(1).strip()
            if not reason:
                problems.append((rel, n, "ds-allow-sin-motivo",
                                 "`// ds-allow:` necesita un motivo", raw.strip()))
            else:
                allows.append((rel, n, reason, [f[0] for f in found]))
            continue
        for rule_id, message in found:
            problems.append((rel, n, rule_id, message, raw.strip()))
    return problems, allows


def main(argv):
    quiet = "--quiet" in argv
    summary = "--summary" in argv
    files = [Path(a).resolve() for a in argv if not a.startswith("--")]
    if not files:
        files = sorted(f for d in UI_DIRS for f in d.rglob("*.swift"))
    files = [f for f in files if not any(d in f.parents for d in TOKEN_DIRS)]

    problems, allows = [], []
    for f in files:
        p, a = lint_file(f)
        problems += p
        allows += a

    if summary:
        from collections import Counter
        for (rel, rule_id), count in sorted(Counter((p[0], p[2]) for p in problems).items()):
            print(f"{count:4d}  {rule_id:22s} {rel}")
    else:
        for rel, n, rule_id, message, line in problems:
            print(f"{rel}:{n}: [{rule_id}] {message}\n    {line}")
    if allows and not quiet:
        print(f"\nExcepciones `// ds-allow` ({len(allows)}):")
        for rel, n, reason, rules in allows:
            print(f"  {rel}:{n} [{', '.join(rules)}] {reason}")
    print(f"\nlint-design: {len(files)} archivos, {len(problems)} problemas, "
          f"{len(allows)} excepciones ds-allow, "
          f"excluidos: Centavo/Theme/ (definición de tokens); "
          f"solo reglas de color en {', '.join(sorted(p.name for p in DRAWINGS))} (dibujos de Atajos).")
    if problems:
        print("lint-design: FALLA. Usa los tokens y componentes de docs/DESIGN_SYSTEM.md.")
        return 1
    print("lint-design: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
