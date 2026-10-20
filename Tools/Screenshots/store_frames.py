#!/usr/bin/env python3
"""The App Store's screenshots in the site's look: a heading and a line over each picture, on the site's dark
surface (the owner chose this on 2026-10-18, "C is it").

    python3 -I Tools/Screenshots/store_frames.py

Reads the raw screenshots `store_shots.sh` made (build/appstore/screenshots/<set>/NN-<surface>.png) and the
captions in Documentation/AppStore/screenshots.json, and writes build/appstore/framed/<set>/NN-<surface>.png at
the same pixel size, without an alpha channel (App Store Connect refuses one). The Vision Pro pictures are framed
the way the site frames them (device_shots.sh): the windows and a third more around them, found against the
empty room (build/appstore/vision-room.png), at 16:9, under a band that holds the heading. iPhone and iPad
pictures show the screen below the heading, in rounded corners. Text is SF Pro, as on the site. Look at every
picture before uploading it.
"""
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent.parent
RAW = ROOT / "build/appstore/screenshots"
OUT = ROOT / "build/appstore/framed"
ROOM = ROOT / "build/appstore/vision-room.png"
CAPTIONS = json.loads((ROOT / "Documentation/AppStore/screenshots.json").read_text())
SF = "/System/Library/Fonts/SFNS.ttf"
# site/static/site.css, dark: --void, --text, --text-muted.
VOID, TEXT, MUTED = (12, 10, 10), (245, 242, 241), (181, 173, 171)


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def greedy(draw, text, f, width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if line and draw.textlength(trial, font=f) > width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def wrap(draw, text, f, width):
    """As few lines as fit, made as even as they go: "Pick up where you left / off" becomes
    "Pick up where / you left off"."""
    lines = greedy(draw, text, f, width)
    narrow = width
    while len(lines) > 1:
        trial = greedy(draw, text, f, narrow - 8)
        if len(trial) > len(lines):
            break
        narrow -= 8
        lines = trial
    return lines


def caption(draw, headline, line, x, y, width, head_size, line_size):
    """Draws the heading and its line from (x, y); returns the y below them."""
    f_head, f_line = font(head_size, "Bold"), font(line_size, "Regular")
    for text in wrap(draw, headline, f_head, width):
        draw.text((x, y), text, font=f_head, fill=TEXT)
        y += round(head_size * 1.18)
    y += round(line_size * 0.35)
    for text in wrap(draw, line, f_line, width):
        draw.text((x, y), text, font=f_line, fill=MUTED)
        y += round(line_size * 1.3)
    return y


def site_crop(shot, room):
    """device_shots.sh's framing: what differs from the empty room, a third larger, at 16:9."""
    diff = ImageChops.difference(shot, room).convert("L").point(lambda v: 255 if v > 28 else 0)
    diff = diff.resize((diff.width // 8, diff.height // 8)).filter(ImageFilter.MinFilter(3))
    box = diff.getbbox()
    if box is None:
        return shot
    left, top, right, bottom = (v * 8 for v in box)
    width = min(shot.width, max((right - left) * 1.35, (bottom - top) * 1.35 * 16 / 9))
    height = width * 9 / 16
    x = min(max((left + right) / 2 - width / 2, 0), shot.width - width)
    y = min(max((top + bottom) / 2 - height / 2, 0), shot.height - height)
    return shot.crop((round(x), round(y), round(x + width), round(y + height)))


def vision(shot, room, headline, line):
    w, h = shot.size
    canvas = Image.new("RGB", (w, h), VOID)
    draw = ImageDraw.Draw(canvas)
    margin = round(w * 0.052)
    band = caption(draw, headline, line, margin, round(h * 0.05), w - 2 * margin,
                   round(h * 0.059), round(h * 0.033)) + round(h * 0.035)
    framed = site_crop(shot, room)
    scaled = framed.resize((w, round(framed.height * w / framed.width)), Image.LANCZOS)
    scene_h = h - band
    top = max(0, (scaled.height - scene_h) // 2)
    canvas.paste(scaled.crop((0, top, w, top + scene_h)), (0, band))
    return canvas


def device(shot, headline, line, corner_ratio):
    """The screen under the heading. Upright, it fills 84% of the width and runs off the foot of the
    picture; on its side, it fits whole below the heading."""
    w, h = shot.size
    canvas = Image.new("RGB", (w, h), VOID)
    draw = ImageDraw.Draw(canvas)
    upright = h > w
    unit = w if upright else h
    margin = round(unit * 0.09)
    y = caption(draw, headline, line, margin, round(unit * 0.11 if upright else unit * 0.07), w - 2 * margin,
                round(unit * 0.072), round(unit * 0.04))
    top = y + round(unit * 0.045)
    if upright:
        inner_w = round(w * 0.84)
        inner_h = round(shot.height * inner_w / shot.width)
    else:
        inner_h = h - top - round(unit * 0.06)
        inner_w = round(shot.width * inner_h / shot.height)
    screen = shot.resize((inner_w, inner_h), Image.LANCZOS)
    radius = round(min(inner_w, inner_h) * corner_ratio)
    x = (w - inner_w) // 2
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w - 1, inner_h - 1), radius=radius, fill=255)
    shadow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, top + 24, x + inner_w, top + 24 + inner_h), radius=radius, fill=150)
    canvas = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    rim = Image.new("L", (inner_w + 6, inner_h + 6), 0)
    ImageDraw.Draw(rim).rounded_rectangle((0, 0, inner_w + 5, inner_h + 5), radius=radius + 3, fill=255)
    canvas.paste(Image.new("RGB", rim.size, (60, 54, 54)), (x - 3, top - 3), rim)
    canvas.paste(screen, (x, top), mask)
    return canvas


def main():
    room = Image.open(ROOM).convert("RGB") if ROOM.exists() else None
    made = 0
    for set_name, entries in CAPTIONS.items():
        if set_name.startswith("_"):
            continue
        out = OUT / set_name
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*.png"):
            old.unlink()
        for entry in entries:
            source = RAW / set_name / f"{entry['file']}.png"
            if not source.exists():
                sys.exit(f"store_frames: {source} is missing; run store_shots.sh first")
            shot = Image.open(source).convert("RGB")
            if set_name == "vision":
                if room is None:
                    sys.exit(f"store_frames: {ROOM} is missing; store_shots.sh vision makes it")
                framed = vision(shot, room, entry["headline"], entry["line"])
            else:
                framed = device(shot, entry["headline"], entry["line"], 0.075 if "iphone" in set_name else 0.03)
            assert framed.size == shot.size and framed.mode == "RGB"
            framed.save(out / f"{entry['file']}.png")
            made += 1
    print(f"store_frames: {made} pictures in {OUT.relative_to(ROOT)}; look at each before uploading")


if __name__ == "__main__":
    main()
