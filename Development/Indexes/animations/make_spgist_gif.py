#!/usr/bin/env python3
"""
Generate an animated GIF explaining an SP-GiST quadtree:
  Phase 1 (INSERT): points are inserted one by one; whenever a quadrant holds
                    more than CAPACITY points it splits into NW/NE/SW/SE at a
                    centroid -- exactly how SP-GiST space-partitions points.
  Phase 2 (QUERY):  a range query rectangle descends the tree, visiting only
                    the quadrants it overlaps (pruning the rest), then reports
                    the matching points.

Pure-Pillow (no matplotlib). Output: spgist.gif

This mirrors Development/Indexes/spgist.md:
  - non-overlapping partitions (quadrants never overlap)
  - a search descends only the relevant partition(s)
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 440           # canvas
PLOT = (20, 40, 420, 420) # the 2-D space drawing area (x0,y0,x1,y1)
PANEL_X = 440             # right-hand text panel start
CAPACITY = 1              # a quadrant splits when it would hold > 1 point
DURATION_MS = 3000

# ---- deterministic sample points (x,y in 0..100) ----
# Chosen so no point lands on (or visually touches) a quadrant boundary. The
# recursive centroid splits of [0,100] fall on 50, then 25/75, then 12.5-steps;
# these points keep a wide margin from all of them, so every point sits clearly
# inside exactly one leaf cell.
POINTS = [(13, 18), (83, 88), (42, 63), (88, 38),
          (58, 13), (13, 83), (63, 42), (33, 33)]

QUERY = (30, 20, 68, 68)  # query rectangle in data coords (x0,y0,x1,y1)

try:
    FONT = ImageFont.truetype("DejaVuSans.ttf", 13)
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
except Exception:
    FONT = FONT_B = FONT_S = ImageFont.load_default()


def to_px(x, y):
    """data coords (0..100) -> pixel coords inside PLOT (y flipped)."""
    px = PLOT[0] + (x / 100.0) * (PLOT[2] - PLOT[0])
    py = PLOT[3] - (y / 100.0) * (PLOT[3] - PLOT[1])
    return px, py


class Quad:
    __slots__ = ("x0", "y0", "x1", "y1", "pts", "children")

    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.pts = []
        self.children = None     # [NW, NE, SW, SE] once split

    def contains(self, p):
        # Half-open on the upper/right edges so a point on a shared split line
        # (x == cx or y == cy) belongs to exactly ONE child, never two. The
        # outer edge at 100 stays inclusive so the top/right border is covered.
        x_ok = self.x0 <= p[0] < self.x1 or (p[0] == self.x1 == 100)
        y_ok = self.y0 <= p[1] < self.y1 or (p[1] == self.y1 == 100)
        return x_ok and y_ok

    def split(self):
        cx = (self.x0 + self.x1) / 2.0
        cy = (self.y0 + self.y1) / 2.0
        self.children = [
            Quad(self.x0, cy, cx, self.y1),   # NW
            Quad(cx, cy, self.x1, self.y1),   # NE
            Quad(self.x0, self.y0, cx, cy),   # SW
            Quad(cx, self.y0, self.x1, cy),   # SE
        ]
        moving, self.pts = self.pts, []
        for p in moving:
            self.insert(p)

    def insert(self, p):
        if self.children is not None:
            for c in self.children:
                if c.contains(p):
                    c.insert(p)
                    return
            self.children[0].insert(p)       # fallback (on a boundary)
            return
        self.pts.append(p)
        if len(self.pts) > CAPACITY:
            self.split()

    def walk(self):
        yield self
        if self.children:
            for c in self.children:
                yield from c.walk()

    def overlaps_rect(self, r):
        return not (self.x1 < r[0] or self.x0 > r[2] or
                    self.y1 < r[1] or self.y0 > r[3])


def draw_grid(d, root, highlight=None, prune=None):
    """Draw all quadrant boundaries; optionally shade highlighted/pruned nodes."""
    highlight = highlight or set()
    prune = prune or set()
    for q in root.walk():
        if q.children:
            continue  # only leaves have visible cells; boundaries drawn below
    # draw every node's rectangle (so splits are visible)
    for q in root.walk():
        p0 = to_px(q.x0, q.y1)
        p1 = to_px(q.x1, q.y0)
        box = [p0[0], p0[1], p1[0], p1[1]]
        if id(q) in prune:
            d.rectangle(box, fill=(238, 238, 238))
        if id(q) in highlight:
            d.rectangle(box, fill=(214, 234, 248))
    for q in root.walk():
        p0 = to_px(q.x0, q.y1)
        p1 = to_px(q.x1, q.y0)
        d.rectangle([p0[0], p0[1], p1[0], p1[1]], outline=(140, 140, 140))


def draw_points(d, pts, matched=None, latest=None):
    matched = matched or set()
    for p in pts:
        px, py = to_px(*p)
        if p == latest:
            color = (231, 76, 60)      # newest insert: red
            r = 6
        elif p in matched:
            color = (39, 174, 96)      # query match: green
            r = 6
        else:
            color = (52, 73, 94)       # normal: dark blue-grey
            r = 4
        d.ellipse([px - r, py - r, px + r, py + r], fill=color)


def frame(root, inserted, title, subtitle, lines,
          query=None, matched=None, latest=None, highlight=None, prune=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((PLOT[0], 10), title, font=FONT_B, fill=(0, 0, 0))
    draw_grid(d, root, highlight=highlight, prune=prune)
    if query is not None:
        q0 = to_px(query[0], query[3])
        q1 = to_px(query[2], query[1])
        d.rectangle([q0[0], q0[1], q1[0], q1[1]],
                    outline=(243, 156, 18), width=3)
    draw_points(d, inserted, matched=matched, latest=latest)
    # right panel
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 26
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 18
    # legend
    ly = H - 70
    d.ellipse([PANEL_X, ly, PANEL_X + 10, ly + 10], fill=(231, 76, 60))
    d.text((PANEL_X + 16, ly - 2), "just inserted", font=FONT_S, fill=(40, 40, 40))
    d.ellipse([PANEL_X, ly + 18, PANEL_X + 10, ly + 28], fill=(39, 174, 96))
    d.text((PANEL_X + 16, ly + 16), "query match", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 36, PANEL_X + 10, ly + 46],
                outline=(243, 156, 18), width=2)
    d.text((PANEL_X + 16, ly + 34), "query region", font=FONT_S, fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=DURATION_MS):
        frames.append(im); durs.append(3000)  # fixed 3s pause per frame

    root = Quad(0, 0, 100, 100)
    inserted = []

    # title / intro
    add(frame(root, inserted,
        "SP-GiST quadtree  —  INSERT",
        "Space partitioning",
        ["The plane starts as one cell.",
         "Each new point goes into the cell",
         "that contains it. When a cell holds",
         "more than one point, it SPLITS into",
         "four non-overlapping quadrants",
         "(NW, NE, SW, SE) at the centroid."]), 1400)

    # Phase 1: inserts
    for i, p in enumerate(POINTS, 1):
        root.insert(p)
        inserted.append(p)
        add(frame(root, inserted,
            "SP-GiST quadtree  —  INSERT",
            f"Insert point {i}/{len(POINTS)}: ({p[0]},{p[1]})",
            ["Point dropped into its quadrant.",
             "If that quadrant already held a",
             "point, it splits into 4 children",
             "and both points move down.",
             "",
             "Partitions never overlap, so each",
             "point lands in exactly one leaf."],
            latest=p), 950)

    # Phase 2: query
    q = QUERY
    overlap_ids, prune_ids, matched = set(), set(), set()
    for node in root.walk():
        if node.children:
            continue
        if node.overlaps_rect(q):
            overlap_ids.add(id(node))
            for p in node.pts:
                if q[0] <= p[0] <= q[2] and q[1] <= p[1] <= q[3]:
                    matched.add(p)
        else:
            prune_ids.add(id(node))

    add(frame(root, inserted,
        "SP-GiST quadtree  —  QUERY",
        "Range query arrives",
        ["Find points inside the orange box.",
         "",
         "The search descends from the root,",
         "visiting only quadrants that overlap",
         "the query and PRUNING the rest."],
        query=q), 1500)
    add(frame(root, inserted,
        "SP-GiST quadtree  —  QUERY",
        "Descend overlapping quadrants",
        ["Blue  = quadrant overlaps query -> visit",
         "Grey  = quadrant pruned (no overlap)",
         "",
         "Only a few cells are examined, not",
         "the whole plane."],
        query=q, highlight=overlap_ids, prune=prune_ids), 2000)
    add(frame(root, inserted,
        "SP-GiST quadtree  —  QUERY",
        f"Matches found: {len(matched)}",
        ["Green points fall inside the query box.",
         "",
         "SP-GiST touched only the overlapping",
         "quadrants to find them -- no full scan.",
         "",
         "This is what powers ORDER BY g <-> p",
         "and containment queries on points."],
        query=q, highlight=overlap_ids, prune=prune_ids,
        matched=matched), 2400)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spgist.gif")
    frames, durs = build_frames()
    durs[-1] = 10000  # pause 10s on the final frame before the loop restarts
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
