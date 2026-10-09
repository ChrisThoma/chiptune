#!/usr/bin/env python3
"""Writes the adaptive launcher icon's two vector layers.

usage: python3 gen-vector-icon.py <res dir>

  drawable/ic_launcher_foreground.xml  the bars in channel colours
  drawable/ic_launcher_monochrome.xml  the same bars as one white silhouette

Both XML files are the source of truth for the icon; re-run this only to change
the geometry or colours. Geometry was measured on the iOS 1024px tile (blocks
stacked upward from y=808, 75px pitch, 65px tall, radius ~12) and is drawn at
TILE_DP inside the 108dp layer so the farthest corner stays within the 66dp
safe circle. Each column fades from its full channel colour at the bottom to
80% over the ground colour at the top, as the iOS icon does.
The background layer is drawable/ic_launcher_background.xml (#0D0D17).
"""
import sys
from pathlib import Path

TILE_DP = 68
GROUND = (0x0D, 0x0D, 0x17)
# (x0, x1, bars, channel colour): Pulse 1, Pulse 2, Triangle, Noise.
COLUMNS = [
    (109, 260, 7, (0xFF, 0x59, 0x73)),
    (328, 478, 4, (0xFF, 0xC7, 0x40)),
    (546, 697, 8, (0x4D, 0xD9, 0xFF)),
    (764, 915, 5, (0xB3, 0x8C, 0xFF)),
]
BLOCK_H, PITCH, BOTTOM, RADIUS, TOP_ALPHA = 65, 75, 808, 12, 0.8


def bar(x0, x1, y1, s, off):
    l, t = off + x0 * s, off + (y1 - BLOCK_H) * s
    w, h, r = (x1 - x0) * s, BLOCK_H * s, RADIUS * s
    return (
        f"M{l + r:.2f},{t:.2f}h{w - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 {r:.2f},{r:.2f}"
        f"v{h - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 -{r:.2f},{r:.2f}h-{w - 2 * r:.2f}"
        f"a{r:.2f},{r:.2f} 0 0 1 -{r:.2f},-{r:.2f}v-{h - 2 * r:.2f}a{r:.2f},{r:.2f} 0 0 1 {r:.2f},-{r:.2f}z"
    )


def vector(paths):
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n'
        '    android:viewportWidth="108" android:viewportHeight="108">\n'
        + "".join(paths)
        + "</vector>\n"
    )


def main():
    s, off = TILE_DP / 1024.0, (108 - TILE_DP) / 2.0
    colored, mono = [], []
    for x0, x1, n, rgb in COLUMNS:
        for i in range(n):
            a = 1.0 - (1.0 - TOP_ALPHA) * i / (n - 1)
            c = "".join(f"{round(a * v + (1 - a) * g):02X}" for v, g in zip(rgb, GROUND))
            d = bar(x0, x1, BOTTOM - i * PITCH, s, off)
            colored.append(f'    <path android:fillColor="#{c}" android:pathData="{d}" />\n')
            mono.append(f"        {d}\n")
    out = Path(sys.argv[1]) / "drawable"
    out.mkdir(parents=True, exist_ok=True)
    (out / "ic_launcher_foreground.xml").write_text(vector(colored))
    (out / "ic_launcher_monochrome.xml").write_text(vector(
        ['    <path android:fillColor="#FFFFFFFF" android:pathData="\n', *mono, '    " />\n']))


if __name__ == "__main__":
    main()
