#!/usr/bin/env python3
"""Render Assets/swatch.tga: a light grey shaded sphere, tinted per colour in-game for colour swatches."""

import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "swatch.tga")
SIZE = 64
SUPERSAMPLE = 4
LIGHT = (-0.45, -0.55, 0.70)  # from the upper left, towards the viewer


def main():
    big = SIZE * SUPERSAMPLE
    radius = big / 2 - SUPERSAMPLE * 2
    centre = big / 2
    length = math.sqrt(sum(c * c for c in LIGHT))
    light = tuple(c / length for c in LIGHT)
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(big):
        for x in range(big):
            dx, dy = (x + 0.5 - centre) / radius, (y + 0.5 - centre) / radius
            d2 = dx * dx + dy * dy
            if d2 > 1:
                continue
            dz = math.sqrt(1 - d2)
            diffuse = max(0.0, dx * light[0] + dy * light[1] + dz * light[2])
            # Bright lit side, soft shadow, darker rim; tinting multiplies, so white keeps the full colour.
            value = 0.78 + 0.22 * diffuse
            value *= 1 - 0.12 * (d2**2)
            highlight = max(0.0, diffuse - 0.95) * 3
            shade = min(1.0, value + highlight)
            rim = math.sqrt(d2)
            grey = round(255 * shade * (0.85 if rim > 0.93 else 1.0))
            pixels[x, y] = (grey, grey, grey, 255)
    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    image.save(OUT, compression=None)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
