#!/usr/bin/env python3
"""Render the shaded spheres in Assets/: swatch.tga, light grey and tinted per colour in-game for colour swatches,
and colorwheel.tga, a hue wheel for the colour picker button."""

import colorsys
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Assets")
SIZE = 64
SUPERSAMPLE = 4
LIGHT = (-0.45, -0.55, 0.70)  # from the upper left, towards the viewer


def swatch_colour(dx, dy, rim):
    return (1.0, 1.0, 1.0)


def wheel_colour(dx, dy, rim):
    # Hue around the centre, red at the top; white in the middle fading to full saturation at the rim.
    hue = (math.atan2(dx, -dy) / (2 * math.pi)) % 1
    return colorsys.hsv_to_rgb(hue, min(1.0, rim * 1.15), 1.0)


def render(name, colour):
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
            shade *= 0.85 if rim > 0.93 else 1.0
            pixels[x, y] = tuple(round(255 * min(1.0, c * shade)) for c in colour(dx, dy, rim)) + (255,)
    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(ASSETS, name)
    image.save(path, compression=None)
    print(f"wrote {path}")


def main():
    render("swatch.tga", swatch_colour)
    render("colorwheel.tga", wheel_colour)


if __name__ == "__main__":
    main()
