#!/usr/bin/env python3
"""
Static labeled diagram of the IVFFlat index structure (single PNG).
Shows: query vector -> compare to list centroids -> probe the nearest list(s)
-> scan only those vectors -> return nearest neighbours. Skipped lists are greyed
and deliberately placed OFF the search/result path.

Pure-Pillow. Output: ivfflat-structure.png
Mirrors AI-Integration/pgvector-ivfflat.md.
"""
import os
import math
import random
from PIL import Image, ImageDraw, ImageFont

W, H = 860, 540
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
GREY = (175, 175, 175)
LGREY = (225, 225, 225)
RED = (192, 57, 43)
ORANGE = (230, 126, 34)

random.seed(5)
RAD = 62


def draw_list(d, cx, cy, lid, scanned):
    ring = GREEN if scanned else GREY
    d.ellipse([cx - RAD, cy - RAD, cx + RAD, cy + RAD], outline=ring, width=2)
    for _ in range(13):
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(8, RAD - 8)
        px, py = cx + r * math.cos(a), cy + r * math.sin(a)
        d.ellipse([px - 3, py - 3, px + 3, py + 3],
                  fill=(GREEN if scanned else LGREY))
    d.rectangle([cx - 7, cy - 7, cx + 7, cy + 7],
                fill=(BLUE if scanned else GREY), outline=DBLUE)
    d.text((cx - 20, cy - RAD - 18), f"list {lid}", font=FM,
           fill=(DBLUE if scanned else GREY))
    tag = "PROBED" if scanned else "skipped"
    d.text((cx - 22, cy + RAD + 4), tag, font=FXS,
           fill=(GREEN if scanned else GREY))


def main():
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((W // 2 - 160, 14), "IVFFlat — cluster, then probe a few",
           font=FB, fill=DBLUE)

    # Layout:
    #   left-center: probed list 1 (on the search path, straight down to results)
    #   right column: skipped lists 2 & 3, well clear of the path and labels
    L1 = (300, 200)        # probed
    L2 = (660, 150)        # skipped
    L3 = (660, 360)        # skipped

    # step-1 label in the top-left gutter (above everything)
    d.text((60, 70), "1) compare query to list centroids", font=FXS, fill=DBLUE)

    # query marker (left), arrow into list 1 (clear of any circle/label)
    qx, qy = 95, 210
    d.line([qx - 13, qy - 13, qx + 13, qy + 13], fill=RED, width=4)
    d.line([qx - 13, qy + 13, qx + 13, qy - 13], fill=RED, width=4)
    d.text((qx - 32, qy + 20), "query vector", font=FM, fill=RED)
    d.line([qx + 16, qy, L1[0] - RAD - 4, L1[1]], fill=DBLUE, width=2)
    d.polygon([(L1[0] - RAD - 4, L1[1]), (L1[0] - RAD - 14, L1[1] - 5),
               (L1[0] - RAD - 14, L1[1] + 5)], fill=DBLUE)

    # the three lists
    draw_list(d, *L1, 1, scanned=True)
    draw_list(d, *L2, 2, scanned=False)
    draw_list(d, *L3, 3, scanned=False)

    # step-2 label points at the skipped/probed decision, in the middle gutter (no overlap)
    d.text((330, 48), "2) pick the nearest list(s) to probe", font=FS, fill=GREEN)
    d.text((470, 250), "skipped lists are", font=FXS, fill=GREY)
    d.text((470, 265), "never read", font=FXS, fill=GREY)

    # step-3 label to the LEFT of the downward path (clear of list 1 and the arrow)
    d.text((40, 300), "3) scan ONLY the", font=FS, fill=GREEN)
    d.text((40, 316), "   probed list's", font=FS, fill=GREEN)
    d.text((40, 332), "   vectors", font=FS, fill=GREEN)

    # result arrow: straight down from list 1 to neighbours — crosses NO other list
    d.line([L1[0], L1[1] + RAD + 18, L1[0], 452], fill=GREEN, width=2)
    d.polygon([(L1[0], 452), (L1[0] - 5, 442), (L1[0] + 5, 442)], fill=GREEN)

    ny = 478
    d.text((L1[0] - 78, ny - 20), "4) nearest neighbours (top-k)", font=FM, fill=DBLUE)
    for i in range(5):
        x = (L1[0] - 48) + i * 24
        d.ellipse([x - 7, ny - 7, x + 7, ny + 7], fill=GREEN)

    # approximate note bottom-right, clear of everything
    d.text((580, 440), "APPROXIMATE:", font=FM, fill=ORANGE)
    for i, ln in enumerate([
        "the true neighbour could be in",
        "a skipped list — raise `probes`",
        "to scan more lists.",
    ]):
        d.text((580, 462 + i * 16), ln, font=FXS, fill=(70, 70, 70))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "ivfflat-structure.png")
    im.save(out)
    print(f"wrote {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
