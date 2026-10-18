#!/usr/bin/env python3
"""The VM's desktop pictures for the website's screenshots: the site's own colours, so the glass in each window
shows a soft wash of them and nothing of anyone's wallpaper. Run with -I.

    python3 -I Tools/Screenshots/macvm/wallpaper.py <out-dir>    # writes wallpaper-dark.png, wallpaper-light.png
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

W, H = 3840, 2400
LOOKS = {
    # base, glow (the icon's red, as the site's hero), second glow
    "dark": ((12, 10, 10), (118, 18, 16), (52, 28, 62)),
    "light": ((248, 246, 245), (246, 196, 190), (214, 206, 232)),
}


def picture(base, glow, second):
    image = Image.new("RGB", (W, H), base)
    layer = Image.new("RGB", (W, H), base)
    draw = ImageDraw.Draw(layer)
    draw.ellipse((W * 0.18, -H * 0.35, W * 0.82, H * 0.55), fill=glow)
    draw.ellipse((W * 0.55, H * 0.45, W * 1.15, H * 1.25), fill=second)
    layer = layer.filter(ImageFilter.GaussianBlur(420))
    return Image.blend(image, layer, 0.85)


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for look, colours in LOOKS.items():
    path = out / f"wallpaper-{look}.png"
    picture(*colours).save(path)
    print(path)
