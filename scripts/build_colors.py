#!/usr/bin/env python3
"""Score every icon's colours into .cache/icon_colors.csv, read by build_data.py.

Each icon gets a vector of colour shares (0-100): pixels are converted to OKLab and softly assigned to the
nearest named colours; pixels near the centre and saturated pixels weigh more. Shares below
MIN_SHARE are written as 0.

Usage:
  python3 scripts/build_colors.py             score the icons in .cache/icons (from extract_icons.py)
  python3 scripts/build_colors.py --sheets    also write .cache/colors/<colour>.png contact sheets
"""

import argparse
import csv
import functools
import math
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
MIN_SHARE = 10
SAMPLE = 28  # icons are scored at this size, after cropping the frame
CROP = 4  # pixels of the 64px icon frame to ignore on each side
SOFTNESS = 0.07  # OKLab distance over which a pixel's weight spreads to neighbouring colours

# Reference colours per name, in sRGB; several shades per name keep dark and light variants in their colour.
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
    "grey": [(125, 125, 125), (75, 75, 78)],
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
NAMES = list(COLORS)


def _centre_weights():
    half = (SAMPLE - 1) / 2
    weights = []
    for y in range(SAMPLE):
        for x in range(SAMPLE):
            radius = math.hypot((x - half) / half, (y - half) / half) / math.sqrt(2)
            weights.append(math.exp(-(radius**2) / (2 * 0.45**2)))
    return weights


# Gaussian falloff from the centre, in image.getdata() order.
CENTRE_WEIGHTS = _centre_weights()


@functools.lru_cache(maxsize=None)
def pixel_info(r5, g5, b5):
    """Chroma and normalized colour shares of a 5-bit-per-channel colour (cached: there are only 32768)."""
    lab = srgb_to_oklab(r5 * 8 + 4, g5 * 8 + 4, b5 * 8 + 4)
    shares = [math.exp(-((math.dist(lab, proto) / SOFTNESS) ** 2) / 2) for _, proto in PROTOTYPES]
    norm = sum(shares) or 1.0
    return math.hypot(lab[1], lab[2]), tuple(s / norm for s in shares)


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


def color_vector(path):
    image = open_icon(path)
    width, height = image.size
    crop = round(CROP * width / 64)
    image = image.crop((crop, crop, width - crop, height - crop)).resize((SAMPLE, SAMPLE), Image.BOX)
    totals = [0.0] * len(PROTOTYPES)
    weight_sum = 0.0
    for (r, g, b, a), centre in zip(image.getdata(), CENTRE_WEIGHTS):
        if a < 32:
            continue
        chroma, shares = pixel_info(r >> 3, g >> 3, b >> 3)
        weight = centre * (0.4 + 0.6 * min(chroma / 0.15, 1.0)) * (a / 255)
        for k, share in enumerate(shares):
            totals[k] += weight * share
        weight_sum += weight
    if weight_sum == 0:
        return {}
    shares = dict.fromkeys(NAMES, 0.0)
    for k, (name, _) in enumerate(PROTOTYPES):
        shares[name] += totals[k]
    return {name: round(100 * value / weight_sum) for name, value in shares.items()}


def score(ids):
    vectors, missing = {}, 0
    for n, file_id in enumerate(ids, 1):
        if not os.path.exists(icon_path(file_id)):
            missing += 1
        else:
            try:
                vectors[file_id] = color_vector(icon_path(file_id))
            except (OSError, ValueError, NotImplementedError) as err:
                log(f"  skip {file_id}: {err}")
        if n % 5000 == 0:
            log(f"  scored {n}/{len(ids)}")
    if missing:
        log(f"{missing} icons have no image; run scripts/extract_icons.py")
    return vectors


def write_csv(vectors):
    with open(OUT, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["id", *COLORS])
        for file_id in sorted(vectors):
            shares = [v if v >= MIN_SHARE else 0 for v in (vectors[file_id].get(name, 0) for name in COLORS)]
            if any(shares):
                writer.writerow([file_id, *shares])
    log(f"wrote {OUT}")


def write_sheets(vectors, per_sheet=96, columns=12):
    os.makedirs(SHEET_DIR, exist_ok=True)
    for name in COLORS:
        top = sorted(vectors, key=lambda i: -vectors[i].get(name, 0))[:per_sheet]
        rows = math.ceil(len(top) / columns)
        sheet = Image.new("RGB", (columns * 66, rows * 66), (20, 20, 20))
        for n, file_id in enumerate(top):
            icon = open_icon(icon_path(file_id)).convert("RGB").resize((64, 64))
            sheet.paste(icon, ((n % columns) * 66 + 1, (n // columns) * 66 + 1))
        sheet.save(os.path.join(SHEET_DIR, f"{name}.png"))
    log(f"wrote contact sheets to {SHEET_DIR}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheets", action="store_true", help="write a contact sheet of the top icons per colour")
    args = parser.parse_args()
    ids = icon_ids()
    vectors = score(ids)
    write_csv(vectors)
    if args.sheets:
        write_sheets(vectors)


if __name__ == "__main__":
    main()
