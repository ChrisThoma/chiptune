#!/usr/bin/env python3
"""Compose the Play Store feature graphic (1024 x 500, no alpha) from the
Android captures shoot.sh writes.

    python3 android/Tools/play/make_feature_graphic.py

Same look as the iOS header (AppStore/creative/make_creative.py, whose
helpers it borrows; AppStore/ is git-excluded, so this runs only where that
folder exists): dark gradient, SF Mono, channel colours, the whole
uncropped app on a tablet with a phone over its lower right. Writes
featureGraphic.png into the supply layout.
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "AppStore", "creative"))
import make_creative as mc  # noqa: E402

IMG = os.path.join(REPO, "android", "fastlane", "metadata", "android", "en-US", "images")
TABLET = os.path.join(IMG, "tenInchScreenshots", "2-playing.png")
PHONE = os.path.join(IMG, "phoneScreenshots", "2-playing.png")
OUT = os.path.join(IMG, "featureGraphic.png")

mc.HEADLINE = "Write your own retro game music"
mc.SUBLINE = "Real 8-bit sound on Android"


def devices(img, box):
    """Tablet with the phone overlapping its lower right, fitted to box."""
    x0, y0, x1, y1 = box
    tab_ar = Image.open(TABLET).width / Image.open(TABLET).height
    ph_ar = Image.open(PHONE).width / Image.open(PHONE).height

    def size(th):
        ph = th * 1.25
        return th * tab_ar + ph * ph_ar * 0.75, ph

    th = y1 - y0
    gw, gh = size(th)
    th *= min((x1 - x0) / gw, (y1 - y0) / gh)
    gw, gh = size(th)
    gx, gy = x0 + ((x1 - x0) - gw) / 2, y0 + ((y1 - y0) - gh) / 2
    ph, tw = round(th * 1.25), round(th * tab_ar)
    for i, c in enumerate(mc.CHANNELS):
        mc.glow(img, gx + gw * (0.2 + 0.2 * i), gy + gh * 0.5, gh * 0.45, c, 34)
    mc.device(img, TABLET, round(gx), round(gy + (gh - th) / 2), round(th), 0.030)
    mc.device(img, PHONE, round(gx + tw - ph * ph_ar * 0.25), round(gy), ph, 0.09)


def main():
    w, h = 1024, 500
    img = mc.ground(w, h)
    x0, y0, x1, y1 = mc.inset(w, h, 0.05, 0.10)
    sw, sh = x1 - x0, y1 - y0
    tw = round(sw * 0.40)
    size = round(sh * 0.12)
    d = ImageDraw.Draw(img)
    while d.textlength(mc.HEADLINE, font=mc.font(size, "Bold")) > tw * 1.9:
        size -= 1
    th = mc.text_height(tw, size)
    mc.text_block(img, x0, y0 + (sh - th) // 2, tw, size)
    devices(img, (x0 + tw + round(sw * 0.04), y0, x1, y1))
    img = img.convert("RGB")
    img.save(OUT, optimize=True)
    print(f"{OUT}  {img.width}x{img.height} {img.mode}")


if __name__ == "__main__":
    main()
