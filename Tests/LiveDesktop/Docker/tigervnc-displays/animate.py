#!/usr/bin/env python3
"""A steady, repeatable picture workload for the disposable VNC fixture.

One borderless window at x y width height (framebuffer pixels): a photographic-looking panel —
smooth colour with grain, the kind of area a server sends as JPEG when it may — cycling through
precomputed frames, and a band of text-like bars that changes colour every frame. It runs at about
15 frames a second until killed, so bytes per second can be compared between client settings.
Everything drawn here is generated; no image files.
"""
import math
import random
import sys
import tkinter as tk

x, y, width, height = (int(value) for value in sys.argv[1:5])
seed = int(sys.argv[5]) if len(sys.argv) > 5 else 1
random.seed(seed)

root = tk.Tk()
root.overrideredirect(True)
root.geometry(f"{width}x{height}+{x}+{y}")
canvas = tk.Canvas(root, width=width, height=height, highlightthickness=0, background="#202428")
canvas.pack()

panel_w, panel_h = min(480, width * 2 // 3), min(320, height * 2 // 3)


def frame(phase):
    image = tk.PhotoImage(width=panel_w, height=panel_h)
    rows = []
    for row in range(panel_h):
        cells = []
        for column in range(panel_w):
            r = 128 + 100 * math.sin((column + phase * 9) / 47.0) + random.randint(-14, 14)
            g = 128 + 100 * math.sin((row + phase * 5) / 31.0 + 1.3) + random.randint(-14, 14)
            b = 128 + 90 * math.cos((column + row) / 59.0 + phase / 3.0) + random.randint(-14, 14)
            cells.append("#%02x%02x%02x" % tuple(max(0, min(255, int(v))) for v in (r, g, b)))
        rows.append("{" + " ".join(cells) + "}")
    image.put(" ".join(rows))
    return image


frames = [frame(phase) for phase in range(6)]
picture = canvas.create_image(20, 20, anchor="nw", image=frames[0])
bars = []
for line in range(14):
    top = 40 + panel_h + line * 9
    if top + 6 > height:
        break
    bars.append(canvas.create_rectangle(20, top, 20 + random.randint(width // 4, width - 40), top + 6, width=0))
tick = 0


def step():
    global tick
    tick += 1
    canvas.itemconfig(picture, image=frames[tick % len(frames)])
    for index, bar in enumerate(bars):
        hue = (tick * 7 + index * 23) % 360
        canvas.itemconfig(bar, fill="#%02x%02x%02x" % (
            int(127 + 127 * math.sin(math.radians(hue))),
            int(127 + 127 * math.sin(math.radians(hue + 120))),
            int(127 + 127 * math.sin(math.radians(hue + 240)))))
    root.after(66, step)


step()
root.mainloop()
