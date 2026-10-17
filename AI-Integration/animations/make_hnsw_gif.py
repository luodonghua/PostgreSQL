#!/usr/bin/env python3
"""
Animated GIF for a pgvector HNSW index:
  HNSW = Hierarchical Navigable Small World. A multilayer proximity graph.
    - Top layers are sparse (few nodes, long links) for coarse navigation.
    - The bottom layer holds every node with short links to near neighbours.
  QUERY: greedy search starts at the top entry point, hops to the closest
         neighbour layer by layer, descending until the bottom layer yields
         the nearest neighbours. No training step; build works on an empty table.

A small real graph (nodes at 2-D positions, kNN links per layer) drives the
frames and the greedy walk is actually computed. Pure-Pillow. Output: hnsw.gif
Mirrors AI-Integration/pgvector-indexes.md.
"""
import os
import math
import random

from PIL import Image, ImageDraw, ImageFont

W, H = 760, 470
PANEL_X = 470

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
    FONT_M = ImageFont.truetype("DejaVuSans.ttf", 12)
except Exception:
    FONT_B = FONT_S = FONT_M = ImageFont.load_default()

GREEN = (39, 174, 96)
ORANGE = (243, 156, 18)
GREY = (170, 170, 170)
BLUE = (41, 128, 185)
RED = (192, 57, 43)
PATHCOL = (243, 156, 18)

random.seed(11)
N = 16

# node positions in data space 0..1
NODES = [(random.random(), random.random()) for _ in range(N)]
QUERY = (0.62, 0.40)

# layer membership: layer 0 = all; higher layers keep fewer (prob 1/2 each)
LAYER_OF = [0] * N
for i in range(N):
    lvl = 0
    while random.random() < 0.5 and lvl < 2:
        lvl += 1
    LAYER_OF[i] = lvl
# guarantee an entry point on the top layer
LAYER_OF[0] = 2
NUM_LAYERS = 3  # layers 2 (top), 1, 0 (bottom)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def nodes_in_layer(L):
    return [i for i in range(N) if LAYER_OF[i] >= L]


def knn_links(L, k=3):
    members = nodes_in_layer(L)
    links = {}
    for i in members:
        others = sorted([j for j in members if j != i],
                        key=lambda j: dist(NODES[i], NODES[j]))
        links[i] = others[:k]
    return links


LINKS = {L: knn_links(L) for L in range(NUM_LAYERS)}


def greedy_path():
    """Greedy descent from top entry point; returns per-layer visited paths."""
    entry = 0
    paths = {}
    cur = entry
    for L in range(NUM_LAYERS - 1, -1, -1):
        visited = [cur]
        improved = True
        while improved:
            improved = False
            for nb in LINKS[L].get(cur, []):
                if dist(NODES[nb], QUERY) < dist(NODES[cur], QUERY):
                    cur = nb
                    visited.append(cur)
                    improved = True
                    break
        paths[L] = visited
    return paths


PATHS = greedy_path()

# layered vertical bands in pixels
BAND_X0, BAND_W = 30, 410
BAND_TOP, BAND_H = 40, 128
GAP = 12


def layer_box(L):
    # L=2 top drawn first (top of image)
    row = (NUM_LAYERS - 1) - L
    y0 = BAND_TOP + row * (BAND_H + GAP)
    return BAND_X0, y0, BAND_W, BAND_H


def to_px(L, p):
    x0, y0, w, h = layer_box(L)
    return (x0 + 20 + p[0] * (w - 40), y0 + 14 + (1 - p[1]) * (h - 28))


def base(title, subtitle, lines):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=(0, 0, 0))
    for L in range(NUM_LAYERS):
        x0, y0, w, h = layer_box(L)
        d.rectangle([x0, y0, x0 + w, y0 + h], outline=(215, 215, 215))
        name = "entry layer (sparse)" if L == NUM_LAYERS - 1 else (
            "bottom layer (all nodes)" if L == 0 else "middle layer")
        d.text((x0 + 4, y0 + 2), f"layer {L} — {name}", font=FONT_S,
               fill=(130, 130, 130))
    y = 46
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 24
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 17
    return im, d


def draw_layer(d, L, show_links=True, path=None, active=False):
    members = nodes_in_layer(L)
    if show_links:
        seen = set()
        for i in members:
            for j in LINKS[L].get(i, []):
                key = tuple(sorted((i, j)))
                if key in seen:
                    continue
                seen.add(key)
                xi, yi = to_px(L, NODES[i])
                xj, yj = to_px(L, NODES[j])
                d.line([xi, yi, xj, yj], fill=(220, 220, 220))
    # path edges
    if path:
        for a, b in zip(path, path[1:]):
            xa, ya = to_px(L, NODES[a])
            xb, yb = to_px(L, NODES[b])
            d.line([xa, ya, xb, yb], fill=PATHCOL, width=3)
    for i in members:
        x, y = to_px(L, NODES[i])
        col = BLUE if active else (150, 150, 150)
        if path and i in path:
            col = PATHCOL
        if path and i == path[-1]:
            col = GREEN
        r = 5 if active else 4
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    # query marker in this layer
    if active:
        qx, qy = to_px(L, QUERY)
        d.line([qx - 6, qy - 6, qx + 6, qy + 6], fill=RED, width=2)
        d.line([qx - 6, qy + 6, qx + 6, qy - 6], fill=RED, width=2)


def build_frames():
    frames, durs = [], []

    def add(im, ms=3000):
        frames.append(im); durs.append(ms)

    # intro: show the three layers
    im, d = base("HNSW  —  multilayer graph",
                 "A hierarchy of proximity graphs",
                 ["HNSW links each vector to its near",
                  "neighbours, in layers:",
                  "",
                  "- top layer: few nodes, long hops",
                  "  (coarse navigation)",
                  "- bottom layer: ALL nodes, short",
                  "  links (fine-grained)",
                  "",
                  "No training step — unlike IVFFlat,",
                  "it can be built on an empty table."])
    for L in range(NUM_LAYERS):
        draw_layer(d, L)
    add(im, 5000)

    # greedy descent, layer by layer
    descr = {
        2: ["Start at the entry point on the top",
            "layer. Greedily hop to the neighbour",
            "closest to the query..."],
        1: ["Drop to the next layer at the best",
            "node found, and keep hopping closer",
            "to the query."],
        0: ["On the bottom layer (all nodes),",
            "refine to the true nearest",
            "neighbours. Return top-k."],
    }
    for L in range(NUM_LAYERS - 1, -1, -1):
        im, d = base("HNSW  —  QUERY (greedy descent)",
                     f"Search layer {L}", descr[L])
        for LL in range(NUM_LAYERS):
            draw_layer(d, LL, path=PATHS[LL] if LL >= L else None,
                       active=(LL == L))
        add(im, 4500)

    # result
    im, d = base("HNSW  —  QUERY",
                 "Nearest neighbours found",
                 ["The green node is the nearest",
                  "neighbour; its bottom-layer links",
                  "give the rest of the top-k.",
                  "",
                  "Only a handful of nodes were",
                  "visited (orange path) instead of",
                  "all of them — fast and high recall.",
                  "",
                  "APPROXIMATE: controlled by",
                  "ef_search (default 40). Higher",
                  "ef_search -> better recall, slower.",
                  "Build: m=16, ef_construction=64."])
    for LL in range(NUM_LAYERS):
        draw_layer(d, LL, path=PATHS[LL], active=(LL == 0))
    add(im, 10000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hnsw.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
