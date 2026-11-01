#!/usr/bin/env python3
"""A screenshot inside one of Apple's product bezels, for the website (the owner, 2026-10-31).

    bezel.py <screen.png> <bezel.png> <out.webp|out.png> [--width PX]

Apple's marketing guidelines ask for its own product bezels wherever an app is shown on a device, used as
they are, and forbid drawing or rendering an Apple device instead. The bezels come from Apple Design
Resources (developer.apple.com/design/resources, Product Bezels), under Apple's Design Resources licence:
they are not part of this repository, so the scripts that call this take the folder holding their PNGs
from `BEZELS`.

A front-facing bezel's screen is a transparent opening the size of the device's screen in pixels, rounded
at its corners and broken by the Dynamic Island or a camera notch. The opening is found by filling the
transparency outward from the middle of the screen, the picture is placed under it, and the bezel is
drawn over it, so the device's own corners, island and notch cover what they cover on the device. The
screenshot must be the screen's own size: a picture of another size is an error, not stretched to fit.
The partly open iPhone Duo bezels are Photoshop files with a warped screen and are made another way
(PhotoCraft's Replace Contents).
"""
import sys
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None


def opening(bezel: Image.Image) -> tuple[int, int, int, int]:
    """The screen's opening: the transparent region reached from the device's middle, as a bounding box."""
    alpha = bezel.getchannel("A")
    width, height = bezel.size
    # The screen's middle. A laptop's screen is its upper part: its middle is above the device's.
    start = next(((x, y) for x, y in [(width // 2, height // 2), (width // 2, int(height * 0.4))]
                  if alpha.getpixel((x, y)) == 0), None)
    if start is None:
        raise SystemExit("bezel.py: no transparent screen at the middle of the bezel")
    mask = alpha.point(lambda a: 0 if a == 0 else 255).convert("L")
    ImageDraw.floodfill(mask, start, 128)
    box = mask.point(lambda v: 255 if v == 128 else 0).getbbox()
    if box is None:
        raise SystemExit("bezel.py: the screen's opening is empty")
    return box


def frame(screen_path: str, bezel_path: str, out_path: str, width: int | None = None) -> None:
    bezel = Image.open(bezel_path).convert("RGBA")
    left, top, right, bottom = opening(bezel)
    screen = Image.open(screen_path).convert("RGBA")
    if screen.size != (right - left, bottom - top):
        raise SystemExit(f"bezel.py: {screen_path} is {screen.size[0]}×{screen.size[1]}, the bezel's screen "
                         f"{right - left}×{bottom - top}: capture at the screen's size")
    picture = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    picture.paste(screen, (left, top))
    # The bezel over the screen: the opening's box lies inside the device, so the screen's corners are under
    # its frame and nothing shows past its edge.
    picture.alpha_composite(bezel)
    if width and width != picture.width:
        picture = picture.resize((width, round(picture.height * width / picture.width)), Image.LANCZOS)
    if out_path.endswith(".webp"):
        picture.save(out_path, "WEBP", quality=88, method=6)
    else:
        picture.save(out_path)
    print(f"{out_path}: {picture.width}x{picture.height}")


if __name__ == "__main__":
    args = sys.argv[1:]
    width = None
    if "--width" in args:
        index = args.index("--width")
        width = int(args[index + 1])
        del args[index:index + 2]
    if len(args) != 3:
        raise SystemExit(__doc__)
    frame(*args, width=width)
