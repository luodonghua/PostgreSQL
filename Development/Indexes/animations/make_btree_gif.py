#!/usr/bin/env python3
"""
Animated GIF for a B-tree index:
  Phase 1 (INSERT): keys inserted one by one into a sorted leaf; when a leaf
                    overflows it SPLITS and a separator is pushed up, growing a
                    balanced tree.
  Phase 2 (SEARCH): a key search descends root -> internal -> leaf by comparing
                    against separator keys, then a range scan walks the sorted
                    leaf level via right-links.

Pure-Pillow. Output: btree.gif   Mirrors Development/Indexes/btree.md.
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 440
PANEL_X = 430
TITLE_Y = 10

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
    FONT_M = ImageFont.truetype("DejaVuSans.ttf", 13)
except Exception:
    FONT_B = FONT_S = FONT_M = ImageFont.load_default()

BLUE = (41, 128, 185)
GREEN = (39, 174, 96)
RED = (231, 76, 60)
GREY = (120, 120, 120)
ORANGE = (243, 156, 18)


def node_box(d, cx, cy, keys, w=38, h=30, highlight=None, found=None):
    """draw a node of up to a few keys centered at (cx,cy)."""
    n = len(keys)
    total = n * w
    x0 = cx - total / 2
    for i, k in enumerate(keys):
        bx0 = x0 + i * w
        box = [bx0, cy - h / 2, bx0 + w, cy + h / 2]
        fill = None
        if found is not None and k == found:
            fill = (213, 245, 227)
        elif highlight is not None and k in highlight:
            fill = (214, 234, 248)
        d.rectangle(box, fill=fill, outline=(90, 90, 90))
        d.text((bx0 + 6, cy - 7), str(k), font=FONT_M, fill=(0, 0, 0))
    return (x0, cy - h / 2, x0 + total, cy + h / 2)


def frame(title, subtitle, lines, tree, path=None, found=None,
          leaf_scan=None):
    """tree: dict with 'root'(list|None), 'internal'(list of lists), 'leaves'(list of lists)."""
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, TITLE_Y), title, font=FONT_B, fill=(0, 0, 0))
    path = path or set()

    leaves = tree["leaves"]
    nleaf = len(leaves)
    leaf_w = 150
    gap = 20
    total_w = nleaf * leaf_w + (nleaf - 1) * gap
    start_x = 20 + max(0, (PANEL_X - 40 - total_w) / 2)
    leaf_y = 320
    centers = []
    # draw leaves + right-links
    prev_right = None
    for li, leaf in enumerate(leaves):
        lx = start_x + li * (leaf_w + gap)
        cx = lx + leaf_w / 2
        centers.append(cx)
        box = [lx, leaf_y - 20, lx + leaf_w, leaf_y + 20]
        scanned = leaf_scan is not None and li in leaf_scan
        d.rectangle(box, outline=(GREEN if scanned else (90, 90, 90)),
                    width=3 if scanned else 1)
        txt = "  ".join(str(k) for k in leaf)
        d.text((lx + 6, leaf_y - 8), txt, font=FONT_M, fill=(0, 0, 0))
        # right-link arrow
        if prev_right is not None:
            d.line([prev_right, leaf_y, lx, leaf_y], fill=GREY, width=1)
            d.polygon([(lx, leaf_y), (lx - 6, leaf_y - 3), (lx - 6, leaf_y + 3)],
                      fill=GREY)
        prev_right = lx + leaf_w
    # internal / root above
    if tree.get("root"):
        rb = node_box(d, (start_x + total_w / 2), 110, tree["root"],
                      highlight=path)
        # links root -> leaves (schematic)
        for cx in centers:
            d.line([(start_x + total_w / 2), 125, cx, leaf_y - 20],
                   fill=(200, 200, 200))
        node_box(d, (start_x + total_w / 2), 110, tree["root"], highlight=path)

    # panel
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 24
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 17

    # legend
    ly = H - 60
    d.rectangle([PANEL_X, ly, PANEL_X + 12, ly + 12], fill=(214, 234, 248),
                outline=(90, 90, 90))
    d.text((PANEL_X + 18, ly - 1), "search path", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 18, PANEL_X + 12, ly + 30], outline=GREEN, width=3)
    d.text((PANEL_X + 18, ly + 17), "scanned / found", font=FONT_S, fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3000):
        frames.append(im); durs.append(ms)

    # We model a leaf capacity of 3 keys; show the tree growing.
    keys = [10, 20, 30, 40, 50, 60, 70]
    leaves = [[]]
    root = None

    def rebuild(ks):
        """produce leaves (cap 3) + a simple one-level root of separators."""
        ks = sorted(ks)
        lv = [ks[i:i + 3] for i in range(0, len(ks), 3)] or [[]]
        rt = [lv[i][0] for i in range(1, len(lv))] if len(lv) > 1 else None
        return lv, rt

    add(frame("B-tree  —  INSERT", "Sorted, balanced tree",
              ["Keys live in sorted leaf pages.",
               "A leaf here holds up to 3 keys.",
               "When a leaf overflows it SPLITS,",
               "and a separator key is pushed up",
               "to the parent -- keeping every",
               "leaf at the same depth."],
              {"root": None, "leaves": [[]]}))

    acc = []
    for k in keys:
        acc.append(k)
        lv, rt = rebuild(acc)
        split = (len(acc) % 3 == 1 and len(acc) > 3)
        add(frame("B-tree  —  INSERT",
                  f"Insert {k}",
                  ["Key placed in sorted order.",
                   ("Leaf overflowed -> SPLIT, push a"
                    if split else "Still fits in the leaf."),
                   ("separator up to the parent." if split else ""),
                   "",
                   "Leaves stay sorted and linked",
                   "left<->right for ordered scans."],
                  {"root": rt, "leaves": lv}, found=k))

    lv, rt = rebuild(acc)
    tree = {"root": rt, "leaves": lv}

    # SEARCH 40
    add(frame("B-tree  —  SEARCH", "Search key = 40",
              ["Descend from the root, comparing",
               "the key against separators to pick",
               "the child, down to one leaf.",
               "",
               "Binary search within each page."],
              tree, path=set(rt or [])))
    # find which leaf holds 40
    tgt_leaf = next(i for i, l in enumerate(lv) if 40 in l)
    add(frame("B-tree  —  SEARCH", "Found 40",
              ["Reached the leaf; 40 -> its heap",
               "ctid is returned.",
               "",
               "One root-to-leaf path, a handful",
               "of page reads -- no table scan."],
              tree, path=set(rt or []), found=40,
              leaf_scan={tgt_leaf}))

    # RANGE scan 30..60
    rng_leaves = {i for i, l in enumerate(lv) if any(30 <= k <= 60 for k in l)}
    add(frame("B-tree  —  RANGE SCAN", "Range 30 .. 60",
              ["For a range or ORDER BY, find the",
               "start leaf, then walk right-links",
               "reading already-sorted keys.",
               "",
               "No sort step is needed -- this is",
               "why ORDER BY ... LIMIT is cheap."],
              tree, leaf_scan=rng_leaves), 10000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "btree.gif")
    frames, durs = build_frames()
    durs[-1] = 10000
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
