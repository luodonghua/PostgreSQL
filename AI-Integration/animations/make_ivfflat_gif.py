#!/usr/bin/env python3
"""
Animated GIF for a pgvector IVFFlat index:
  Phase 1 (BUILD):  k-means clusters the stored vectors into `lists` cells;
                    each list keeps a center and the vectors assigned to it.
  Phase 2 (QUERY):  the query vector is compared to the `lists` centers; only
                    the `probes` nearest lists are scanned, the rest are SKIPPED.

A real (tiny) k-means over 2-D points drives the frames, so the picture reflects
the actual algorithm. Pure-Pillow. Output: ivfflat.gif
Mirrors AI-Integration/pgvector-indexes.md.
"""
import os
import math
import random

from PIL import Image, ImageDraw, ImageFont

W, H = 760, 460
PANEL_X = 470

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
    FONT_M = ImageFont.truetype("DejaVuSans.ttf", 12)
except Exception:
    FONT_B = FONT_S = FONT_M = ImageFont.load_default()

GREEN = (39, 174, 96)
ORANGE = (243, 156, 18)
GREY = (150, 150, 150)
LIGHTGREY = (238, 238, 238)
BLUE = (41, 128, 185)
RED = (192, 57, 43)
LIST_COLORS = [(41, 128, 185), (39, 174, 96), (155, 89, 182), (211, 84, 0)]

# --- plane mapping (data space 0..1 -> pixels) ---
PX0, PY0, PW, PH = 30, 60, 410, 360


def to_px(p):
    return (PX0 + p[0] * PW, PY0 + (1 - p[1]) * PH)


# --- real data + k-means ---
random.seed(7)
K = 4


def gen_points():
    centers = [(0.25, 0.75), (0.75, 0.78), (0.2, 0.25), (0.78, 0.25)]
    pts = []
    for cx, cy in centers:
        for _ in range(12):
            pts.append((min(1, max(0, cx + random.uniform(-0.12, 0.12))),
                        min(1, max(0, cy + random.uniform(-0.12, 0.12)))))
    return pts


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def kmeans(pts, k, iters=8):
    cs = random.sample(pts, k)
    assign = [0] * len(pts)
    for _ in range(iters):
        for i, p in enumerate(pts):
            assign[i] = min(range(k), key=lambda c: dist(p, cs[c]))
        for c in range(k):
            members = [pts[i] for i in range(len(pts)) if assign[i] == c]
            if members:
                cs[c] = (sum(m[0] for m in members) / len(members),
                         sum(m[1] for m in members) / len(members))
    return cs, assign


POINTS = gen_points()
CENTERS, ASSIGN = kmeans(POINTS, K)
QUERY = (0.32, 0.62)
PROBES = 1


def base(title, subtitle, lines):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 12), title, font=FONT_B, fill=(0, 0, 0))
    d.rectangle([PX0, PY0, PX0 + PW, PY0 + PH], outline=(210, 210, 210))
    y = 46
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 24
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 17
    return im, d


def draw_points(d, colored, show_centers=False, probe_lists=None,
                skip_lists=None, show_query=False):
    probe_lists = probe_lists if probe_lists is not None else set()
    skip_lists = skip_lists if skip_lists is not None else set()
    for i, p in enumerate(POINTS):
        x, y = to_px(p)
        if colored:
            col = LIST_COLORS[ASSIGN[i]]
            if skip_lists and ASSIGN[i] in skip_lists:
                col = LIGHTGREY
        else:
            col = (120, 120, 120)
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=col)
    if show_centers:
        for c in range(K):
            cx, cy = to_px(CENTERS[c])
            col = LIST_COLORS[c]
            ring = col
            if c in probe_lists:
                ring = GREEN
            elif c in skip_lists:
                ring = GREY
            d.rectangle([cx - 7, cy - 7, cx + 7, cy + 7], outline=ring, width=3)
            d.text((cx + 9, cy - 6), f"list {c}", font=FONT_S, fill=ring)
    if show_query:
        qx, qy = to_px(QUERY)
        d.line([qx - 7, qy - 7, qx + 7, qy + 7], fill=RED, width=3)
        d.line([qx - 7, qy + 7, qx + 7, qy - 7], fill=RED, width=3)
        d.text((qx + 9, qy + 4), "query", font=FONT_S, fill=RED)


def build_frames():
    frames, durs = [], []

    def add(im, ms=3000):
        frames.append(im); durs.append(ms)

    im, d = base("IVFFlat  —  BUILD (needs data first)",
                 "Start: unindexed vectors",
                 ["IVFFlat must see data before it can",
                  "build: it learns clusters from the",
                  "vectors already in the table.",
                  "",
                  "Here: 48 vectors in 2-D (real",
                  "embeddings live in 100s of dims)."])
    draw_points(d, colored=False)
    add(im)

    im, d = base("IVFFlat  —  BUILD (k-means)",
                 f"Cluster into lists = {K}",
                 ["k-means groups the vectors into",
                  f"`lists` cells ({K} here).",
                  "",
                  "Each list stores:",
                  "  - a CENTER (centroid)",
                  "  - the vectors assigned to it.",
                  "",
                  "Default lists = 100. Rule of thumb:",
                  "rows/1000 (<=1M rows),",
                  "sqrt(rows) (>1M rows)."])
    draw_points(d, colored=True, show_centers=True)
    add(im, 5000)

    # QUERY: nearest `probes` centers
    order = sorted(range(K), key=lambda c: dist(QUERY, CENTERS[c]))
    probe = set(order[:PROBES])
    skip = set(order[PROBES:])

    im, d = base("IVFFlat  —  QUERY",
                 f"Find the {PROBES} nearest list center(s)",
                 ["Compare the query to the list",
                  "CENTERS only (not every vector).",
                  "",
                  f"probes = {PROBES} (default 1): scan",
                  f"the {PROBES} closest list(s).",
                  "",
                  "Higher probes -> better recall,",
                  "slower. Start near sqrt(lists)."])
    draw_points(d, colored=True, show_centers=True, probe_lists=probe,
                skip_lists=skip, show_query=True)
    add(im, 4000)

    im, d = base("IVFFlat  —  QUERY",
                 f"Scan {PROBES} list, skip {len(skip)} lists",
                 ["Only vectors in the probed list(s)",
                  "(green) are compared to the query.",
                  "",
                  "Grey lists are SKIPPED entirely —",
                  "that is the speedup.",
                  "",
                  "APPROXIMATE: the true nearest",
                  "neighbour could sit in a skipped",
                  "list. Raise probes to reduce the",
                  "chance of missing it."])
    draw_points(d, colored=True, show_centers=True, probe_lists=probe,
                skip_lists=skip, show_query=True)
    add(im, 9000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ivfflat.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
