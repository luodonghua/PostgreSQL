#!/usr/bin/env python3
"""
Static labeled diagram of the HNSW index structure (single PNG).
Shows the layered graph: Layer 2 (sparse entry) -> Layer 1 (sparser) ->
Layer 0 (dense, all points), with a greedy search path descending from the
entry point to the nearest neighbours.

Pure-Pillow. Output: hnsw-structure.png
Mirrors AI-Integration/pgvector-hnsw.md.
"""
import os
import math
import random
from PIL import Image, ImageDraw, ImageFont

W, H = 820, 560
try:
    FB = ImageFont.truetype("DejaVuSans-Bold.ttf", 17)
    FM = ImageFont.truetype("DejaVuSans-Bold.ttf", 13)
    FS = ImageFont.truetype("DejaVuSans.ttf", 12)
    FXS = ImageFont.truetype("DejaVuSans.ttf", 11)
except Exception:
    FB = FM = FS = FXS = ImageFont.load_default()

BLUE = (41, 128, 185)
DBLUE = (30, 70, 120)
GREEN = (39, 174, 96)
GREY = (170, 170, 170)
LGREY = (215, 215, 215)
RED = (192, 57, 43)
ORANGE = (230, 126, 34)
PATH = (230, 126, 34)

random.seed(9)


def layer_points(n, y, jitter=0):
    pts = []
    for i in range(n):
        x = 180 + i * ((W - 320) / (n - 1))
        yy = y + (random.uniform(-jitter, jitter) if jitter else 0)
        pts.append((x, yy))
    return pts


def main():
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((W // 2 - 150, 14), "HNSW — a layered neighbour graph", font=FB, fill=DBLUE)

    # three layers (top sparse -> bottom dense)
    L2_y, L1_y, L0_y = 90, 240, 410
    L2 = layer_points(4, L2_y)
    L1 = layer_points(7, L1_y, 10)
    L0 = layer_points(13, L0_y, 14)

    # layer labels / bands
    for (y, name) in [(L2_y, "Layer 2  — entry layer (very sparse, long hops)"),
                      (L1_y, "Layer 1  — middle layer (sparser)"),
                      (L0_y, "Layer 0  — bottom layer (ALL vectors, dense)")]:
        d.line([150, y + 46, W - 110, y + 46], fill=LGREY)
        d.text((150, y - 40), name, font=FM, fill=(110, 110, 110))

    def links(pts, k, col):
        for i, p in enumerate(pts):
            order = sorted(range(len(pts)), key=lambda j: abs(pts[j][0] - p[0]))
            for j in order[1:k + 1]:
                d.line([p[0], p[1], pts[j][0], pts[j][1]], fill=col)

    links(L0, 3, LGREY)
    links(L1, 2, LGREY)
    links(L2, 2, LGREY)

    def dots(pts, r=5, col=BLUE):
        for (x, y) in pts:
            d.ellipse([x - r, y - r, x + r, y + r], fill=col)

    dots(L0); dots(L1); dots(L2)

    # inter-layer "drop down" connectors (same node descends)
    for a, b in [(L2[1], L1[2]), (L1[2], L0[4])]:
        d.line([a[0], a[1] + 6, b[0], b[1] - 6], fill=LGREY)

    # greedy path (entry -> ... -> nearest)
    entry = L2[0]
    path = [L2[0], L2[1], L1[2], L1[3], L0[4], L0[5]]
    for a, b in zip(path, path[1:]):
        d.line([a[0], a[1], b[0], b[1]], fill=PATH, width=3)
    for (x, y) in path:
        d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=PATH)
    # highlight start and result
    sx, sy = entry
    d.ellipse([sx - 7, sy - 7, sx + 7, sy + 7], outline=RED, width=3)
    d.text((sx - 18, sy - 26), "entry", font=FXS, fill=RED)
    rx, ry = path[-1]
    d.ellipse([rx - 7, ry - 7, rx + 7, ry + 7], fill=GREEN)

    # query marker
    qx, qy = rx + 70, ry - 10
    d.line([qx - 10, qy - 10, qx + 10, qy + 10], fill=RED, width=3)
    d.line([qx - 10, qy + 10, qx + 10, qy - 10], fill=RED, width=3)
    d.text((qx - 12, qy + 14), "query", font=FXS, fill=RED)

    # step annotations
    d.text((W - 300, L2_y + 2), "start at entry point", font=FXS, fill=PATH)
    d.text((W - 300, L1_y + 2), "hop closer, drop a layer", font=FXS, fill=PATH)
    d.text((W - 300, L0_y + 2), "refine to nearest (green)", font=FXS, fill=GREEN)

    # result
    ny = 500
    d.text((150, ny - 18), "nearest neighbours (top-k)", font=FM, fill=DBLUE)
    for i in range(5):
        x = 165 + i * 24
        d.ellipse([x - 7, ny - 7, x + 7, ny + 7], fill=GREEN)
    d.text((440, ny - 10),
           "few nodes visited (orange path) — fast & high recall; no training step",
           font=FXS, fill=(70, 70, 70))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "hnsw-structure.png")
    im.save(out)
    print(f"wrote {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
