#!/usr/bin/env python3
"""Renders the Android launcher icon from the iOS AppIcon (icon-1024.png).

usage: render-android.py <icon-1024.png> <res dir> <play-icon-512.png>

Outputs, under the res dir:
  mipmap-*/ic_launcher_foreground.png  adaptive foreground: the four bars only,
                                       keyed out of the iOS tile, on transparency
  mipmap-*/ic_launcher.png, ic_launcher_round.png   legacy icons (pre-26)
  drawable/ic_launcher_monochrome.xml  vector silhouette for themed icons
and the 512px Play Store icon.

The adaptive layer is 108dp and only its centre 72dp survives a mask, with a
guaranteed 66dp circle. The tile is drawn at TILE_DP so the farthest bar
corner (about 0.49 of the tile's width from the centre) stays inside that circle.
The background is the solid #0D0D17 in drawable/ic_launcher_background.xml.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

TILE_DP = 68
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

# Bar geometry measured on the 1024 tile: column x ranges, blocks stacked
# upward from y=808 with a 75px pitch, 65px tall, corner radius ~12.
COLUMNS = [(109, 260, 7), (328, 478, 4), (546, 697, 8), (764, 915, 5)]
BLOCK_H, PITCH, BOTTOM, RADIUS = 65, 75, 808, 12


def key_bars(icon: Image.Image) -> Image.Image:
    """Alpha from chroma: the ground is near grey, the bars are saturated.
    Edge pixels are un-mixed from the ground colour so no dark fringe remains."""
    rgb = np.asarray(icon.convert("RGB"), dtype=np.float64)
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    # Bars never drop below ~90 of chroma; the ground stays under ~14.
    alpha = np.clip((chroma - 14.0) / (90.0 - 14.0), 0.0, 1.0)
    ground = np.array([14.0, 14.0, 21.0])
    safe = np.maximum(alpha, 1e-3)[..., None]
    colour = np.clip((rgb - ground * (1.0 - alpha[..., None])) / safe, 0, 255)
    out = np.dstack([colour, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def foreground(bars: Image.Image, density: float) -> Image.Image:
    layer_px = round(108 * density)
    tile_px = round(TILE_DP * density)
    layer = Image.new("RGBA", (layer_px, layer_px), (0, 0, 0, 0))
    tile = bars.resize((tile_px, tile_px), Image.LANCZOS)
    offset = (layer_px - tile_px) // 2
    layer.paste(tile, (offset, offset))
    return layer


def legacy(icon: Image.Image, density: float, round_shape: bool) -> Image.Image:
    px = round(48 * density)
    img = icon.convert("RGBA").resize((px, px), Image.LANCZOS)
    scale = 4
    mask = Image.new("L", (px * scale, px * scale), 0)
    d = ImageDraw.Draw(mask)
    if round_shape:
        d.ellipse((0, 0, px * scale - 1, px * scale - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, px * scale - 1, px * scale - 1), radius=int(px * scale * 0.18), fill=255)
    mask = mask.resize((px, px), Image.LANCZOS)
    img.putalpha(mask)
    return img


def monochrome_vector() -> str:
    """The bars as one path in a 108dp viewport, tile centred at TILE_DP."""
    s = TILE_DP / 1024.0
    off = (108 - TILE_DP) / 2.0
    paths = []
    for x0, x1, count in COLUMNS:
        for i in range(count):
            y1 = BOTTOM - i * PITCH
            y0 = y1 - BLOCK_H
            l, t = off + x0 * s, off + y0 * s
            w, h, r = (x1 - x0) * s, BLOCK_H * s, RADIUS * s
            paths.append(
                f"M{l + r:.2f},{t:.2f}h{w - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 {r:.2f},{r:.2f}"
                f"v{h - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 -{r:.2f},{r:.2f}h-{w - 2 * r:.2f}"
                f"a{r:.2f},{r:.2f} 0 0 1 -{r:.2f},-{r:.2f}v-{h - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 {r:.2f},-{r:.2f}z"
            )
    body = "\n".join(f"        {p}" for p in paths)
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n'
        '    android:viewportWidth="108" android:viewportHeight="108">\n'
        '    <path android:fillColor="#FFFFFFFF" android:pathData="\n'
        f"{body}\n"
        '    " />\n'
        "</vector>\n"
    )


def main() -> None:
    icon_path, res_dir, play_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    icon = Image.open(icon_path).convert("RGBA")
    if icon.size != (1024, 1024):
        sys.exit(f"expected a 1024x1024 icon, got {icon.size}")
    bars = key_bars(icon)
    for name, density in DENSITIES.items():
        folder = res_dir / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        foreground(bars, density).save(folder / "ic_launcher_foreground.png", optimize=True)
        legacy(icon, density, False).save(folder / "ic_launcher.png", optimize=True)
        legacy(icon, density, True).save(folder / "ic_launcher_round.png", optimize=True)
    (res_dir / "drawable").mkdir(parents=True, exist_ok=True)
    (res_dir / "drawable" / "ic_launcher_monochrome.xml").write_text(monochrome_vector())
    play_path.parent.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").resize((512, 512), Image.LANCZOS).save(play_path, optimize=True)


if __name__ == "__main__":
    main()
