#!/usr/bin/env python3
"""A made-up evening landscape for the website's Picture look (D84): a sky from deep blue to dusk, a
low sun, and three ranges of mountains, darker as they come nearer. Drawn here, so the picture behind
a terminal on the site is no one's photograph and the same every run.

    python3 -I Tools/Screenshots/landscape.py out.png
"""
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 2400, 1500
SKY_TOP, SKY_HORIZON = (30, 48, 150), (168, 132, 120)
SUN = (255, 211, 148)
RANGES = [  # colour, base height (fraction of the picture from the top), roughness
    ((70, 58, 92), 0.58, 0.09),
    ((45, 38, 70), 0.69, 0.07),
    ((27, 24, 46), 0.79, 0.05),
]


def ridge(rng, base, rough):
    """Points along a mountain range's top edge, every 60 pixels, from the left edge to the right."""
    points, y = [], base * HEIGHT
    for x in range(0, WIDTH + 60, 60):
        y += rng.uniform(-rough, rough) * HEIGHT * 0.6
        y = min(max(y, (base - rough * 1.6) * HEIGHT), (base + rough) * HEIGHT)
        points.append((x, y))
    return points


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rng = random.Random(84)
    picture = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(picture)
    horizon = int(HEIGHT * 0.78)
    for y in range(HEIGHT):
        t = min(1.0, y / horizon)
        draw.line([(0, y), (WIDTH, y)],
                  fill=tuple(round(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_HORIZON)))
    sun_x, sun_y, radius = WIDTH * 0.69, HEIGHT * 0.44, HEIGHT * 0.1
    draw.ellipse([sun_x - radius, sun_y - radius, sun_x + radius, sun_y + radius], fill=SUN)
    for colour, base, rough in RANGES:
        draw.polygon(ridge(rng, base, rough) + [(WIDTH, HEIGHT), (0, HEIGHT)], fill=colour)
    picture.filter(ImageFilter.GaussianBlur(1.2)).save(sys.argv[1])
    print(sys.argv[1])


if __name__ == "__main__":
    main()
