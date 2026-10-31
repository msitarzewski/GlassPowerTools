#!/usr/bin/env python3
"""The VM's desktop pictures for the website's Mac screenshots: macOS's own default (the owner, 2026-10-30: "I'd
love it if we could shoot all of these with the default Apple background visible"), its light and its dark
version. The default is a moving wallpaper; each picture is the still where the owner's desktop showed it,
stretched to the screen as macOS draws it. It is macOS 27's default, which the VM's macOS 26 doesn't have, and
Apple's artwork: made here from the copy macOS keeps once that wallpaper has been shown, never kept in the
repository. Needs ffmpeg. Run with -I.

    python3 -I Tools/Screenshots/macvm/wallpaper.py <out-dir> [WxH]   # wallpaper-dark.png, wallpaper-light.png
"""
import subprocess
import sys
from pathlib import Path
from PIL import Image

VIDEOS = Path.home() / "Library/Application Support/com.apple.wallpaper/aerials/videos"
# The default's landscape versions, by their ids in macOS's wallpaper catalogue (WallpaperAerialsExtension's
# entries.json: the "macOS" dynamic wallpaper).
LOOKS = {"light": "4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19", "dark": "C6AECFD2-A365-4504-9E2C-F86343F9421F"}
# Seconds into each video: where the owner's desktop stood (his screenshot of 2026-10-30, matched frame by frame).
STILL = "64.5"

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
width, height = (int(v) for v in (sys.argv[2] if len(sys.argv) > 2 else "2880x1800").split("x"))
for look, asset in LOOKS.items():
    video = VIDEOS / f"{asset}.mov"
    if not video.exists():
        sys.exit(f"wallpaper: macOS's {look} default isn't on this Mac yet. Choose the macOS wallpaper in "
                 "System Settings ▸ Wallpaper once, and macOS downloads it.")
    still = out / f"wallpaper-{look}-still.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", STILL, "-i", str(video), "-frames:v", "1", str(still)],
                   check=True)
    Image.open(still).convert("RGB").resize((width, height), Image.LANCZOS).save(out / f"wallpaper-{look}.png")
    still.unlink()
    print(out / f"wallpaper-{look}.png")
