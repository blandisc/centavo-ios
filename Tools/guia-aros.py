#!/usr/bin/env python3
"""Turns the screenshots of GuideScreenshotsTests into the guide's imagesets, with the brass ring.

    python3 Tools/guia-aros.py CARPETA IDIOMA [--salida DIR] [--png]

CARPETA is what `xcrun xcresulttool export attachments` left (the «guia-atajos-<idioma>»
artifact of the CI job «Guía de Atajos»: PNGs plus manifest.json); IDIOMA is `es` or `en`.
It writes `guia27-XX-nombre.imageset` (es) or `guia27-XX-nombre-en.imageset` (en) into --salida
(default: Centavo/Resources/Assets.xcassets), each with its Contents.json, for the same asset
names as the Spanish set:

    python3 Tools/guia-aros.py ~/Downloads/guia-atajos-en en
    python3 Tools/guia-aros.py build/capturas en --salida build/guia   # what the CI does

Each picture is the screenshot's whole width scaled to 900 px, cut to a band as tall as the
Spanish picture of the same name (so `GuideFrame.focus`, set as fractions of the Spanish one,
lands on the same place), with the band placed so the marked element sits where the Spanish
`focus` centres (TABLA, `centro`). The ring is a brass capsule (Theme.brass, #D0A44E) around the
element the test marked («<foto>-marca»: its frame in pixels), a little larger than it; results
(«Así debe verse») keep their place and get no ring. With `sips` (macOS) the file is HEIC like
the Spanish set; elsewhere, or with --png, PNG. Look at each picture once: a band or a crop
that reads wrong is fixed in TABLA, not by hand.

Only the standard library: PNG in and out, the scaling and the ring are done here.
"""

import argparse
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ANCHO = 900                     # Width of every guide picture, as the Spanish set.
LATON = (0xD0, 0xA4, 0x4E)      # Theme.brass.
GROSOR = 6.0                    # Ring stroke, in output pixels.
HOLGURA = 10.0                  # Room between the element and the ring, in output pixels.
MARGEN_FILA = 12.0              # A ring that takes a whole row stops this far from the edges.

# asset (without «-en»), snap of GuideScreenshotsTests, height of the Spanish picture at 900 px
# wide (its band), and where the marked element's centre goes in the band (0 top, 1 bottom:
# the centre of the Spanish `focus`), or "arriba"/"abajo" to stick the band to that edge.
TABLA = [
    ("guia27-01-mas",            "01-todos-los-atajos",          892, 0.836),
    ("guia27-01b-editar",        "01b-describir-un-atajo",       818, "arriba"),
    ("guia27-02-automatizacion", "02-nuevo-atajo",               470, 0.425),
    ("guia27-03-notificacion",   "04-notificacion-en-la-lista",  860, 0.691),
    ("guia27-04-app",            "05-bloque-notificacion",       552, 0.58),
    ("guia27-05-wallet",         "06b-wallet-en-la-lista",       860, 0.631),
    ("guia27-06-con-wallet",     "07-con-wallet",                490, 0.5),
    ("guia27-07-accion",         "08-buscar-accion",             470, 0.5),
    ("guia27-08-campo",          "09-accion-agregada",           614, 0.58),
    ("guia27-09-variable",       "10b-variable-a-la-vista",      716, 0.893),
    ("guia27-09a-barra",         "10-elegir-variable",           716, 0.833),
    ("guia27-10-guardar",        "11b-opciones-del-disparador",  392, "arriba"),
    ("guia27-11-listo",          "12-guardada",                  532, 0.5),
    ("guia27-12-flechita",       "13-flechita",                  170, 0.5),
    ("guia27-13-subtitulo",      "14-subtitulo",                 626, 0.535),
    ("guia27-14-mostrar",        "15-mostrar",                   198, 0.5),
    ("guia27-15-accion-lista",   "16-accion-lista",              368, 0.215),
]

# A name xcresulttool gives an attachment: «<name>_<index>_<UUID>.<ext>».
SUGERIDO = re.compile(r"^(?P<name>.+?)_\d+_[0-9A-Fa-f-]{36}$")


# MARK: - PNG

def leer_png(path):
    """(width, height, rows) with rows a list of bytearrays of RGB."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} no es PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    width, height, depth, color, _, _, interlace = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color)
    if channels is None or depth not in (8, 16) or interlace:
        raise ValueError(f"{path}: PNG que este script no lee (color {color}, {depth} bits, entrelazado {interlace})")
    bpp = channels * depth // 8
    stride = width * bpp
    raw = zlib.decompress(b"".join(idat))
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif kind == 2:
            line = bytearray((a + b) & 0xFF for a, b in zip(line, previous))
        elif kind == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = previous[i]
                c = previous[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        rows.append(line)
        previous = line
    out = []
    for line in rows:
        if depth == 16:
            line = line[0::2]
        if channels == 4:
            rgb = bytearray(len(line) * 3 // 4)
            rgb[0::3], rgb[1::3], rgb[2::3] = line[0::4], line[1::4], line[2::4]
        elif channels == 3:
            rgb = bytearray(line)
        elif channels == 2:
            rgb = bytearray(b for g in line[0::2] for b in (g, g, g))
        else:
            rgb = bytearray(b for g in line for b in (g, g, g))
        out.append(rgb)
    return width, height, out


def escribir_png(path, width, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n"
                           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, len(rows), 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9))
                           + chunk(b"IEND", b""))


# MARK: - Scaling and the ring

def pesos(src, dst):
    """For each output index, [(source index, weight)]: the box each output pixel covers."""
    ratio = src / dst
    out = []
    for i in range(dst):
        a, b = i * ratio, (i + 1) * ratio
        cells = []
        j = int(a)
        while j < b and j < src:
            w = min(b, j + 1) - max(a, j)
            if w > 1e-9:
                cells.append((j, w / ratio))
            j += 1
        out.append(cells)
    return out


def escalar(rows, width, out_w, out_h):
    """Box-scales RGB rows (width px each) to out_w × out_h."""
    cols = pesos(width, out_w)
    wide = []
    for row in rows:
        line = bytearray(out_w * 3)
        for x, cells in enumerate(cols):
            r = g = b = 0.0
            for j, w in cells:
                k = j * 3
                r += row[k] * w; g += row[k + 1] * w; b += row[k + 2] * w
            line[x * 3], line[x * 3 + 1], line[x * 3 + 2] = min(255, round(r)), min(255, round(g)), min(255, round(b))
        wide.append(line)
    out = []
    for cells in pesos(len(wide), out_h):
        acc = [0.0] * (out_w * 3)
        for j, w in cells:
            src = wide[j]
            for k in range(out_w * 3):
                acc[k] += src[k] * w
        out.append(bytearray(min(255, round(v)) for v in acc))
    return out


def aro(rows, width, rect):
    """Draws a brass capsule ring around rect (x, y, w, h, output pixels), anti-aliased."""
    x, y, w, h = rect
    x, y, w, h = x - HOLGURA, y - HOLGURA, w + 2 * HOLGURA, h + 2 * HOLGURA
    radius = min(w, h) / 2
    cx, cy = x + w / 2, y + h / 2
    half_w, half_h = w / 2 - radius, h / 2 - radius
    half = GROSOR / 2
    height = len(rows)
    for py in range(max(0, int(y - GROSOR)), min(height, int(math.ceil(y + h + GROSOR)) + 1)):
        row = rows[py]
        for px in range(max(0, int(x - GROSOR)), min(width, int(math.ceil(x + w + GROSOR)) + 1)):
            # Distance from the pixel centre to the capsule's outline.
            dx = max(abs(px + 0.5 - cx) - half_w, 0.0)
            dy = max(abs(py + 0.5 - cy) - half_h, 0.0)
            d = abs(math.hypot(dx, dy) - radius)
            cover = max(0.0, min(1.0, half + 0.5 - d))
            if cover > 0:
                k = px * 3
                for c in range(3):
                    row[k + c] = round(row[k + c] * (1 - cover) + LATON[c] * cover)


# MARK: - The attachments

def adjuntos(carpeta):
    """{attachment name: path}, the last one of each name (a retried test repeats them)."""
    carpeta = Path(carpeta)
    found = {}
    manifest = carpeta / "manifest.json"
    if manifest.exists():
        entries = []
        for test in json.loads(manifest.read_text()):
            entries.extend(test.get("attachments", []))
        entries.sort(key=lambda a: a.get("timestamp", 0))
        for a in entries:
            stem = Path(a.get("suggestedHumanReadableName", a["exportedFileName"])).stem
            m = SUGERIDO.match(stem)
            found[m.group("name") if m else stem] = carpeta / a["exportedFileName"]
    else:
        for path in sorted(carpeta.iterdir()):
            m = SUGERIDO.match(path.stem)
            found[m.group("name") if m else path.stem] = path
    return found


def como_png(path, tmp):
    """The screenshot as PNG: as it is, or converted with sips (macOS) if it came otherwise."""
    if Path(path).read_bytes()[:4] == b"\x89PNG":
        return path
    if not shutil.which("sips"):
        raise ValueError(f"{path} no es PNG y aquí no hay sips para convertirlo")
    out = Path(tmp) / (Path(path).stem + ".png")
    subprocess.run(["sips", "-s", "format", "png", str(path), "--out", str(out)], check=True, capture_output=True)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("carpeta")
    parser.add_argument("idioma", choices=["es", "en"])
    parser.add_argument("--salida", default=str(Path(__file__).resolve().parent.parent / "Centavo/Resources/Assets.xcassets"))
    parser.add_argument("--png", action="store_true", help="PNG aunque haya sips (HEIC)")
    args = parser.parse_args()

    suffix = "" if args.idioma == "es" else "-" + args.idioma
    found = adjuntos(args.carpeta)
    heic = shutil.which("sips") is not None and not args.png
    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    missing = []
    with tempfile.TemporaryDirectory() as tmp:
        for asset, shot, band_h, centre in TABLA:
            name = asset + suffix
            source = found.get(shot + suffix)
            if source is None:
                missing.append(f"{name} (falta la captura «{shot + suffix}»)")
                continue
            width, height, rows = leer_png(como_png(source, tmp))
            scale = ANCHO / width
            band = min(height, round(band_h / scale))
            mark = None
            if (shot + suffix + "-marca") in found:
                mark = json.loads(Path(found[shot + suffix + "-marca"]).read_text())
                # The mark is in the screenshot's pixels; one taken at another size is rescaled.
                k = width / mark.get("pantallaW", width)
                mark.update(x=mark["x"] * k, y=mark["y"] * k, w=mark["w"] * k, h=mark["h"] * k)
            if centre == "arriba":
                top = 0
            elif centre == "abajo":
                top = height - band
            else:
                middle = mark["y"] + mark["h"] / 2 if mark else height / 2
                top = round(middle - centre * band)
            top = max(0, min(height - band, top))
            out_h = round(band * scale)
            picture = escalar(rows[top:top + band], width, ANCHO, out_h)
            if mark and mark.get("aro", True):
                x, w = mark["x"] * scale, mark["w"] * scale
                if mark.get("fila"):
                    x, w = MARGEN_FILA + HOLGURA, ANCHO - 2 * (MARGEN_FILA + HOLGURA)
                aro(picture, ANCHO, (x, (mark["y"] - top) * scale, w, mark["h"] * scale))
            elif mark is None:
                missing.append(f"{name}: sin «-marca», quedó sin aro y con la franja al centro")

            folder = salida / f"{name}.imageset"
            if folder.exists():
                shutil.rmtree(folder)
            folder.mkdir()
            png = Path(tmp) / f"{name}.png"
            escribir_png(png, ANCHO, picture)
            filename = f"{name}.heic" if heic else f"{name}.png"
            if heic:
                subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "70", str(png),
                                "--out", str(folder / filename)], check=True, capture_output=True)
            else:
                shutil.copy(png, folder / filename)
            (folder / "Contents.json").write_text(json.dumps({
                "images": [{"filename": filename, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")
            print(f"ok  {folder.name}  {ANCHO}×{out_h}  (franja {top}–{top + band} de {height} px)")
    for line in missing:
        print(f"OJO {line}", file=sys.stderr)
    print(f"{len(TABLA) - sum(1 for m in missing if 'falta la captura' in m)} de {len(TABLA)} imágenes en {salida}")


if __name__ == "__main__":
    main()
