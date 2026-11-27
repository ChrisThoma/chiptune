#!/usr/bin/env python3
"""Makes the Mac app icon set from the iOS icon art.

The iOS icon is full-bleed square art that iOS masks itself. A Mac icon
carries its own shape: Apple's template puts an 824 pt rounded square
(corner radius about 185) centered on a 1024 canvas, and leaves the margin
transparent. Same art, that shape, no added shadow.

    python3 scripts/make_mac_icon.py
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
OUT = ROOT / "Sources/Mac/Assets.xcassets/AppIcon.appiconset"

CANVAS, BODY, RADIUS = 1024, 824, 185
SUPERSAMPLE = 4


def master() -> Image.Image:
    art = Image.open(SOURCE).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)
    # Drawn large and scaled down so the corners are antialiased.
    big = BODY * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1),
                                           radius=RADIUS * SUPERSAMPLE, fill=255)
    mask = mask.resize((BODY, BODY), Image.LANCZOS)
    art.putalpha(mask)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - BODY) // 2
    canvas.alpha_composite(art, (offset, offset))
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon = master()
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            name = f"icon-{size}@{scale}x.png"
            icon.resize((px, px), Image.LANCZOS).save(OUT / name)
            images.append({"filename": name, "idiom": "mac",
                           "scale": f"{scale}x", "size": f"{size}x{size}"})
    (OUT / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (OUT.parent / "Contents.json").write_text(json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


if __name__ == "__main__":
    main()
