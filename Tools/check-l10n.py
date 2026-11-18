#!/usr/bin/env python3
"""Every text the person sees has its English (2026-11-18, docs/DECISIONS.md).

Usage: python3 Tools/check-l10n.py <DerivedData>      (the CI: build/dd)

The build (SWIFT_EMIT_LOC_STRINGS, project.yml) leaves a `.stringsdata` per Swift file: the
keys the compiler extracted from that file's localized literals (`Text("…")`, `HintText("…")`,
`String(localized: "…")`, App Intents' titles…), each the Spanish text exactly. This checks
that each key of the tables `Localizable` and `AppShortcuts` is in its String Catalog with a
non-empty English value:

- the app's files (and CentavoCore's) → Centavo/Resources/Localizable.xcstrings
- the widgets' (what the CentavoWidgets target compiles: CentavoWidgets/, and the
  Centavo/Theme files and the intent it shares) → CentavoWidgets/Localizable.xcstrings
- the App Shortcuts' phrases → Centavo/Resources/AppShortcuts.xcstrings

A Theme file is compiled by both targets, so its keys need both catalogs: each target reads
its own at run time. Left out: «Mi dinero» (Centavo/Screens/Money/, hidden for launch), the
DEBUG demos (Centavo/Debug/), DesignSystemCatalog.swift, the tests, `#Preview` blocks, and
keys with no letters («%@ · %@»). CentavoCore's `String(localized: "…", bundle: .main)` are
also read from its sources, in case the package build emits no `.stringsdata`.

Prints the missing keys by file and exits 1 when any is missing. Python 3, standard library.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_CATALOG = "Centavo/Resources/Localizable.xcstrings"
WIDGET_CATALOG = "CentavoWidgets/Localizable.xcstrings"
SHORTCUTS_CATALOG = "Centavo/Resources/AppShortcuts.xcstrings"

IGNORED_PREFIXES = ("Centavo/Screens/Money/", "Centavo/Debug/", "CentavoTests/", "CentavoUITests/",
                    "Packages/CentavoCore/Tests/")
IGNORED_FILES = ("DesignSystemCatalog.swift",)

# A printf placeholder as the compiler writes them in a key: %@, %lld, %1$@, %.2f, %%.
FORMAT = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGcCsSaAp%]")
PLACEHOLDER = "\u0000"


def relative(path):
    """The path from the repo's root, with forward slashes; as given when it is outside."""
    if not path:
        return ""
    absolute = os.path.abspath(path)
    if absolute.startswith(ROOT + os.sep):
        return os.path.relpath(absolute, ROOT).replace(os.sep, "/")
    return path.replace(os.sep, "/")


def has_letters(key):
    return any(c.isalpha() for c in FORMAT.sub("", key))


def load_catalog(path):
    """The catalog's `strings`, or {} when it is missing or unreadable (said once)."""
    full = os.path.join(ROOT, path)
    try:
        with open(full, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as error:
        print(f"check-l10n: no pude leer {path}: {error}")
        return {}
    strings = data.get("strings") if isinstance(data, dict) else None
    return strings if isinstance(strings, dict) else {}


def has_value(node):
    """True when a localization node (a stringUnit, or variations of them) has some text."""
    if not isinstance(node, dict):
        return False
    unit = node.get("stringUnit")
    if isinstance(unit, dict) and isinstance(unit.get("value"), str) and unit["value"].strip():
        return True
    variations = node.get("variations")
    if isinstance(variations, dict):
        for kind in variations.values():
            if isinstance(kind, dict) and kind and all(has_value(v) for v in kind.values()):
                return True
    return False


def has_english(strings, key):
    entry = strings.get(key)
    if not isinstance(entry, dict):
        return False
    if entry.get("shouldTranslate") is False:
        return True
    localizations = entry.get("localizations")
    if not isinstance(localizations, dict):
        return False
    return has_value(localizations.get("en"))


# --- #Preview blocks: their literals are only for Xcode's canvas, never localized. -------------

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "0": "\0"}


def preview_ranges(text):
    """Where each `#Preview { … }` sits in the file, by counting braces outside strings."""
    ranges = []
    for match in re.finditer(r"#Preview\b", text):
        start = text.find("{", match.end())
        if start < 0:
            continue
        depth, i, in_string = 0, start, False
        while i < len(text):
            c = text[i]
            if in_string:
                if c == "\\":
                    i += 1
                elif c == '"':
                    in_string = False
            elif c == '"':
                in_string = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        ranges.append((match.start(), i))
    return ranges


def normalized_literal(body):
    """A source literal as a comparable key: escapes decoded, each \\(…) a placeholder."""
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt == "(":
                depth, j = 1, i + 2
                while j < len(body) and depth:
                    depth += {"(": 1, ")": -1}.get(body[j], 0)
                    j += 1
                out.append(PLACEHOLDER)
                i = j
                continue
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def normalized_key(key):
    return FORMAT.sub(lambda m: "%" if m.group(0) == "%%" else PLACEHOLDER, key)


_preview_cache = {}


def preview_only_literals(source):
    """The literals of `source` that appear only inside #Preview blocks (normalized)."""
    if source in _preview_cache:
        return _preview_cache[source]
    inside, outside = set(), set()
    try:
        with open(source, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        _preview_cache[source] = set()
        return set()
    ranges = preview_ranges(text)
    for match in LITERAL.finditer(text):
        value = normalized_literal(match.group(1))
        if any(a <= match.start() <= b for a, b in ranges):
            inside.add(value)
        else:
            outside.add(value)
    _preview_cache[source] = inside - outside
    return _preview_cache[source]


# --- What the build extracted. ------------------------------------------------------------------

def stringsdata_files(derived):
    for folder, _, files in os.walk(derived):
        for name in files:
            if name.endswith(".stringsdata"):
                yield os.path.join(folder, name)


def read_stringsdata(path):
    """(source, {table: [key, …]}), or None when the file is not what it should be."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    source = data.get("source") if isinstance(data.get("source"), str) else ""
    tables = data.get("tables")
    found = {}
    if isinstance(tables, dict):
        for table, entries in tables.items():
            keys = []
            if isinstance(entries, list):
                for entry in entries:
                    if isinstance(entry, dict) and isinstance(entry.get("key"), str):
                        keys.append(entry["key"])
                    elif isinstance(entry, str):
                        keys.append(entry)
            elif isinstance(entries, dict):
                keys.extend(k for k in entries if isinstance(k, str))
            found[table] = keys
    return source, found


def catalog_for(stringsdata_path, source_rel):
    """Which catalog a file's Localizable keys belong to: the target that compiled it."""
    parts = stringsdata_path.replace(os.sep, "/")
    if "/CentavoWidgets.build/" in parts:
        return WIDGET_CATALOG
    if source_rel.startswith("CentavoWidgets/"):
        return WIDGET_CATALOG
    return APP_CATALOG


def ignored(source_rel):
    if source_rel.startswith(IGNORED_PREFIXES):
        return True
    return os.path.basename(source_rel) in IGNORED_FILES


# CentavoCore: String(localized: "…", bundle: .main), read from the sources.
CORE_LITERAL = re.compile(r'String\(\s*localized:\s*"((?:[^"\\\n]|\\.)*)"[^)]*?bundle:\s*\.main')


def core_keys():
    """(source, pattern) for each CentavoCore literal; a pattern matches its possible keys."""
    base = os.path.join(ROOT, "Packages", "CentavoCore", "Sources")
    for folder, _, files in os.walk(base):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(folder, name)
            try:
                with open(path, encoding="utf-8") as f:
                    text = f.read()
            except OSError:
                continue
            for match in CORE_LITERAL.finditer(text):
                yield relative(path), normalized_literal(match.group(1))


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 2
    derived = argv[1]
    if not os.path.isdir(derived):
        print(f"check-l10n: no existe {derived}; corre primero el build.")
        return 2

    catalogs = {path: load_catalog(path) for path in (APP_CATALOG, WIDGET_CATALOG, SHORTCUTS_CATALOG)}
    missing = {}   # source → {(catalog, key)}
    files = 0
    checked = 0

    def check(source_rel, catalog, key, preview=frozenset()):
        nonlocal checked
        if not key or not has_letters(key):
            return
        if normalized_key(key) in preview:
            return
        checked += 1
        if not has_english(catalogs[catalog], key):
            missing.setdefault(source_rel or "(sin archivo)", set()).add((catalog, key))

    for path in stringsdata_files(derived):
        read = read_stringsdata(path)
        if read is None:
            continue
        files += 1
        source, tables = read
        source_rel = relative(source)
        if ignored(source_rel):
            continue
        preview = preview_only_literals(source) if source and os.path.isfile(source) else set()
        for key in tables.get("Localizable", []):
            check(source_rel, catalog_for(path, source_rel), key, preview)
        for key in tables.get("AppShortcuts", []):
            check(source_rel, SHORTCUTS_CATALOG, key, preview)

    if files == 0:
        print(f"check-l10n: el build no dejó ningún .stringsdata en {derived} "
              "(¿falta SWIFT_EMIT_LOC_STRINGS en project.yml?).")
        return 2

    # CentavoCore, from its sources: a literal with \(…) matches a key with %@ or %lld there.
    app = catalogs[APP_CATALOG]
    normalized_app = {normalized_key(k) for k in app if has_english(app, k)}
    for source_rel, literal in core_keys():
        if not has_letters(literal.replace(PLACEHOLDER, "")):
            continue
        checked += 1
        if literal not in normalized_app:
            shown = literal.replace(PLACEHOLDER, "%@")
            missing.setdefault(source_rel, set()).add((APP_CATALOG, shown))

    if not missing:
        print(f"check-l10n: OK, {checked} textos con inglés ({files} archivos .stringsdata).")
        return 0

    total = sum(len(keys) for keys in missing.values())
    print(f"check-l10n: faltan {total} textos en inglés. Agrégalos al catálogo indicado, "
          "con la clave en español tal cual y el valor en «en»:")
    for source in sorted(missing):
        print(f"\n{source}")
        for catalog, key in sorted(missing[source]):
            print(f"  {catalog}: {json.dumps(key, ensure_ascii=False)}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
