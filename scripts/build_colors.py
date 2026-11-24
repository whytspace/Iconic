#!/usr/bin/env python3
"""Find every icon's dominant colors into .cache/icon_colors.csv, read by build_data.py.

Each icon gets up to MAX_COLORS colors in OKLab with their weight (the part of the icon they cover) and the
name of the nearest reference color. Pixels near the center and saturated pixels weigh more.

Usage:
  python3 scripts/build_colors.py             analyze the icons in .cache/icons (from extract_icons.py)
  python3 scripts/build_colors.py --sheets    also write .cache/colors/<color>.png contact sheets
"""

import argparse
import csv
import functools
import math
import multiprocessing
import os
import struct
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAGO_CACHE = os.path.join(ROOT, ".cache", "wago")
ICON_CACHE = os.path.join(ROOT, ".cache", "icons")
SHEET_DIR = os.path.join(ROOT, ".cache", "colors")
OUT = os.path.join(ROOT, ".cache", "icon_colors.csv")

BRANCHES = ["wowf", "wow"]
SAMPLE = 28  # icons are analyzed at this size, after cropping the frame
CROP = 4  # pixels of the 64px icon frame to ignore on each side
MAX_COLORS = 4
ITERATIONS = 10  # k-means rounds
MERGE = 0.05  # OKLab distance under which two found colors become one
MIN_WEIGHT = 0.05  # smaller colors are dropped

# Reference colors per name, in sRGB, for the contact sheets; must match COLOR_REFS in Search.lua.
COLORS = {
    "red": [(205, 40, 40), (120, 20, 25)],
    "orange": [(230, 125, 30), (170, 85, 25)],
    "yellow": [(235, 210, 55), (190, 160, 40)],
    "green": [(60, 170, 55), (30, 90, 30), (150, 210, 70)],
    "teal": [(30, 165, 160), (20, 95, 100)],
    "blue": [(45, 95, 215), (25, 45, 120), (110, 170, 240)],
    "purple": [(130, 60, 195), (70, 30, 105)],
    "pink": [(240, 120, 190), (200, 60, 140)],
    "brown": [(115, 72, 40), (150, 105, 65)],
    "black": [(18, 18, 20)],
    "white": [(235, 235, 230)],
    "gray": [(176, 176, 176), (125, 125, 125), (75, 75, 78)],
}


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def srgb_to_oklab(r, g, b):
    def linear(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = linear(r), linear(g), linear(b)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


PROTOTYPES = [(name, srgb_to_oklab(*rgb)) for name, shades in COLORS.items() for rgb in shades]


def _center_weights():
    half = (SAMPLE - 1) / 2
    weights = []
    for y in range(SAMPLE):
        for x in range(SAMPLE):
            radius = math.hypot((x - half) / half, (y - half) / half) / math.sqrt(2)
            weights.append(math.exp(-(radius**2) / (2 * 0.45**2)))
    return weights


# Gaussian falloff from the center, in image.getdata() order.
CENTER_WEIGHTS = _center_weights()


@functools.lru_cache(maxsize=None)
def pixel_lab(r5, g5, b5):
    """OKLab of a 5-bit-per-channel color (cached: there are only 32768)."""
    return srgb_to_oklab(r5 * 8 + 4, g5 * 8 + 4, b5 * 8 + 4)


def color_name(lab):
    return min(PROTOTYPES, key=lambda proto: math.dist(lab, proto[1]))[0]


def icon_ids():
    """Icon file IDs of both clients."""
    ids = set()
    for branch in BRANCHES:
        path = os.path.join(WAGO_CACHE, f"{branch}-ManifestInterfaceData.csv")
        if not os.path.exists(path):
            sys.exit(f"missing {path}; run scripts/build_data.py first")
        with open(path, encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                if row["FilePath"].lower().replace("/", "\\").startswith("interface\\icons"):
                    ids.add(int(row["ID"]))
    return sorted(ids)


def icon_path(file_id):
    return os.path.join(ICON_CACHE, f"{file_id}.blp")


def open_icon(path):
    """RGBA image of an icon file. Pillow lacks BLP2 encoding 3 (uncompressed BGRA), decoded here."""
    with open(path, "rb") as handle:
        head = handle.read(148)
    if head[:4] == b"BLP2" and head[8] == 3:
        width, height = struct.unpack("<II", head[12:20])
        offset, size = struct.unpack("<I", head[20:24])[0], struct.unpack("<I", head[84:88])[0]
        with open(path, "rb") as handle:
            handle.seek(offset)
            pixels = handle.read(size)
        return Image.frombytes("RGBA", (width, height), pixels, "raw", "BGRA")
    return Image.open(path).convert("RGBA")


def distance2(p, q):
    return (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2


def nearest(point, centers):
    return min(range(len(centers)), key=lambda k: distance2(point, centers[k]))


def dominant_colors(file_id):
    """Up to MAX_COLORS (OKLab, weight) pairs by weighted k-means, heaviest first; weights sum to 1."""
    image = open_icon(icon_path(file_id))
    width, height = image.size
    crop = round(CROP * width / 64)
    image = image.crop((crop, crop, width - crop, height - crop)).resize((SAMPLE, SAMPLE), Image.BOX)
    histogram = {}
    for (r, g, b, a), center in zip(image.getdata(), CENTER_WEIGHTS):
        if a < 32:
            continue
        lab = pixel_lab(r >> 3, g >> 3, b >> 3)
        chroma = math.hypot(lab[1], lab[2])
        weight = center * (0.4 + 0.6 * min(chroma / 0.15, 1.0)) * (a / 255)
        histogram[lab] = histogram.get(lab, 0.0) + weight
    points = list(histogram.items())
    total = sum(w for _, w in points)
    if not total:
        return []
    # Start from the heaviest color, then repeatedly the one farthest from the chosen ones, weighted by mass.
    centers = [max(points, key=lambda pw: pw[1])[0]]
    while len(centers) < min(MAX_COLORS, len(points)):
        centers.append(max(points, key=lambda pw: pw[1] * min(distance2(pw[0], c) for c in centers))[0])
    for _ in range(ITERATIONS):
        sums = [[0.0, 0.0, 0.0, 0.0] for _ in centers]
        for point, weight in points:
            s = sums[nearest(point, centers)]
            s[0] += point[0] * weight
            s[1] += point[1] * weight
            s[2] += point[2] * weight
            s[3] += weight
        centers = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) if s[3] else c for s, c in zip(sums, centers)]
    weights = [0.0] * len(centers)
    for point, weight in points:
        weights[nearest(point, centers)] += weight
    found = sorted(([c, w / total] for c, w in zip(centers, weights) if w > 0), key=lambda cw: -cw[1])
    merged = []
    for center, weight in found:
        for other in merged:
            if distance2(center, other[0]) < MERGE**2:
                both = other[1] + weight
                other[0] = tuple((other[0][j] * other[1] + center[j] * weight) / both for j in range(3))
                other[1] = both
                break
        else:
            merged.append([center, weight])
    kept = [m for m in merged if m[1] >= MIN_WEIGHT]
    kept_total = sum(w for _, w in kept)
    return [(c, w / kept_total) for c, w in kept]


def analyze(file_id):
    try:
        return file_id, dominant_colors(file_id)
    except (OSError, ValueError, NotImplementedError) as err:
        log(f"  skip {file_id}: {err}")
        return file_id, []


def analyze_all(ids):
    present = [i for i in ids if os.path.exists(icon_path(i))]
    if len(present) < len(ids):
        log(f"{len(ids) - len(present)} icons have no image; run scripts/extract_icons.py")
    colors = {}
    with multiprocessing.Pool() as pool:
        for n, (file_id, found) in enumerate(pool.imap(analyze, present, chunksize=64), 1):
            if found:
                colors[file_id] = found
            if n % 5000 == 0:
                log(f"  analyzed {n}/{len(present)}")
    return colors


def write_csv(colors):
    with open(OUT, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, lineterminator="\n")
        header = ["id"]
        for k in range(1, MAX_COLORS + 1):
            header += [f"l{k}", f"a{k}", f"b{k}", f"w{k}", f"name{k}"]
        writer.writerow(header)
        for file_id in sorted(colors):
            row = [file_id]
            for (L, a, b), weight in colors[file_id]:
                row += [round(L * 100), round(a * 100), round(b * 100), round(weight * 100), color_name((L, a, b))]
            writer.writerow(row)
    log(f"wrote {OUT}")


def write_sheets(colors, per_sheet=96, columns=12):
    """Per reference color name, the icons with the most weight in colors of that name."""
    os.makedirs(SHEET_DIR, exist_ok=True)
    shares = {}
    for file_id, found in colors.items():
        for lab, weight in found:
            key = (file_id, color_name(lab))
            shares[key] = shares.get(key, 0.0) + weight
    for name in COLORS:
        top = sorted(colors, key=lambda i: -shares.get((i, name), 0.0))[:per_sheet]
        rows = math.ceil(len(top) / columns)
        sheet = Image.new("RGB", (columns * 66, rows * 66), (20, 20, 20))
        for n, file_id in enumerate(top):
            icon = open_icon(icon_path(file_id)).convert("RGB").resize((64, 64))
            sheet.paste(icon, ((n % columns) * 66 + 1, (n // columns) * 66 + 1))
        sheet.save(os.path.join(SHEET_DIR, f"{name}.png"))
    log(f"wrote contact sheets to {SHEET_DIR}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheets", action="store_true", help="write a contact sheet of the top icons per color")
    args = parser.parse_args()
    colors = analyze_all(icon_ids())
    write_csv(colors)
    if args.sheets:
        write_sheets(colors)


if __name__ == "__main__":
    main()
