#!/usr/bin/env python3
"""
Generate an animated GIF explaining a GiST R-tree over 2-D boxes:
  Phase 1 (INSERT): rectangles are inserted one by one; they are grouped into
                    leaf nodes, and each node gets a BOUNDING BOX (the Union of
                    its entries). Crucially, sibling bounding boxes may OVERLAP
                    -- the defining difference from SP-GiST.
  Phase 2 (QUERY):  a query box is tested against each node's bounding box with
                    the `consistent` predicate; the search descends EVERY node
                    whose bounding box overlaps the query (possibly several),
                    then rechecks the actual entries.

Pure-Pillow (no matplotlib). Output: gist.gif

Mirrors Development/Indexes/gist.md:
  - hierarchical bounding predicates that may overlap
  - search descends all consistent subtrees (not just one)
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 440
PLOT = (20, 40, 420, 420)
PANEL_X = 440
DURATION_MS = 3000

# data rectangles (x0,y0,x1,y1) in 0..100 space, grouped into two leaf nodes
NODE_A = [(22, 40, 38, 56), (8, 66, 24, 82), (26, 46, 42, 62)]    # upper-left cluster
NODE_B = [(44, 34, 60, 50), (72, 10, 88, 26), (50, 30, 66, 46)]   # lower-right cluster
ALL = [("A", r) for r in NODE_A] + [("B", r) for r in NODE_B]

QUERY = (30, 30, 60, 60)   # MBR A and MBR B are DISJOINT, but the query overlaps
                           # each -> both visited; 2 clear matches + 1 non-match each

COL_A = (41, 128, 185)     # node A entries (blue)
COL_B = (142, 68, 173)     # node B entries (purple)
COL_BBOX_A = (174, 214, 241)
COL_BBOX_B = (215, 189, 226)

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
except Exception:
    FONT_B = FONT_S = ImageFont.load_default()


def to_px(x, y):
    px = PLOT[0] + (x / 100.0) * (PLOT[2] - PLOT[0])
    py = PLOT[3] - (y / 100.0) * (PLOT[3] - PLOT[1])
    return px, py


def rect_px(r):
    a = to_px(r[0], r[3])
    b = to_px(r[2], r[1])
    return [a[0], a[1], b[0], b[1]]


def union(rects):
    xs0 = min(r[0] for r in rects); ys0 = min(r[1] for r in rects)
    xs1 = max(r[2] for r in rects); ys1 = max(r[3] for r in rects)
    return (xs0, ys0, xs1, ys1)


def overlaps(a, b):
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def frame(entries, title, subtitle, lines, show_bbox=False,
          query=None, visit=None, matched=None, latest=None):
    """entries: list of (node, rect). visit: set of node names highlighted."""
    visit = visit or set()
    matched = matched or set()
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((PLOT[0], 10), title, font=FONT_B, fill=(0, 0, 0))
    # outer space
    d.rectangle([PLOT[0], PLOT[1], PLOT[2], PLOT[3]], outline=(170, 170, 170))

    # bounding boxes (drawn first, behind entries)
    if show_bbox:
        for name, col_fill, col_line in (("A", COL_BBOX_A, COL_A),
                                         ("B", COL_BBOX_B, COL_B)):
            rects = [r for n, r in entries if n == name]
            if not rects:
                continue
            bb = union(rects)
            px = rect_px(bb)
            if name in visit:
                d.rectangle(px, outline=col_line, width=4)
                d.text((px[0] + 3, px[1] + 2), f"MBR {name} (visit)",
                       font=FONT_S, fill=col_line)
            else:
                d.rectangle(px, outline=col_line, width=2)
                d.text((px[0] + 3, px[1] + 2), f"MBR {name}",
                       font=FONT_S, fill=col_line)

    # entries
    for name, r in entries:
        col = COL_A if name == "A" else COL_B
        px = rect_px(r)
        if r == latest:
            d.rectangle(px, outline=(231, 76, 60), width=3)
        elif r in matched:
            d.rectangle(px, outline=(39, 174, 96), width=3)
            d.rectangle([px[0]+2, px[1]+2, px[2]-2, px[3]-2], fill=(213, 245, 227))
        else:
            d.rectangle(px, outline=col, width=1)

    # query box
    if query is not None:
        qp = rect_px(query)
        d.rectangle(qp, outline=(243, 156, 18), width=3)

    # panel
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 26
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 18

    # legend
    ly = H - 88
    d.rectangle([PANEL_X, ly, PANEL_X + 12, ly + 12], outline=COL_A, width=2)
    d.text((PANEL_X + 18, ly - 1), "node A entries", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 18, PANEL_X + 12, ly + 30], outline=COL_B, width=2)
    d.text((PANEL_X + 18, ly + 17), "node B entries", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 36, PANEL_X + 12, ly + 48], outline=(243, 156, 18), width=2)
    d.text((PANEL_X + 18, ly + 35), "query box", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 54, PANEL_X + 12, ly + 66], outline=(39, 174, 96), width=2)
    d.text((PANEL_X + 18, ly + 53), "query match", font=FONT_S, fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=DURATION_MS):
        frames.append(im); durs.append(3000)  # fixed 3s pause per frame

    entries = []
    add(frame(entries,
        "GiST R-tree  —  INSERT",
        "Bounding predicates",
        ["GiST groups entries into nodes.",
         "Each node stores a bounding box",
         "(an MBR) = Union of its entries.",
         "",
         "Unlike SP-GiST partitions, sibling",
         "bounding boxes MAY OVERLAP."]), 1400)

    # Phase 1: insert each rectangle
    for i, (name, r) in enumerate(ALL, 1):
        entries.append((name, r))
        add(frame(entries,
            "GiST R-tree  —  INSERT",
            f"Insert box {i}/{len(ALL)} into node {name}",
            ["New entry added to its node.",
             "The node's bounding box grows",
             "(Union) to cover the new entry.",
             "",
             "`penalty` chooses which node to",
             "grow least; `union` makes the MBR."],
            show_bbox=True, latest=r), 900)

    # settle frame: both MBRs (disjoint)
    add(frame(entries,
        "GiST R-tree  —  INSERT",
        "Two nodes, two bounding boxes",
        ["MBR A covers the upper-left cluster.",
         "MBR B covers the lower-right cluster.",
         "",
         "Here the two MBRs are disjoint. (In",
         "general GiST MBRs are ALLOWED to",
         "overlap -- that's the key contrast",
         "with SP-GiST's strict partitions.)"],
        show_bbox=True), 1600)

    # Phase 2: query
    q = QUERY
    visit = set()
    matched = set()
    for name, grp in (("A", NODE_A), ("B", NODE_B)):
        if overlaps(union(grp), q):
            visit.add(name)
            for r in grp:
                if overlaps(r, q):
                    matched.add(r)

    add(frame(entries,
        "GiST R-tree  —  QUERY",
        "Query box arrives",
        ["Find entries overlapping the orange",
         "box (operator &&).",
         "",
         "`consistent(MBR, query)` is tested at",
         "each node: does the query overlap",
         "this bounding box?"],
        show_bbox=True, query=q), 1400)

    add(frame(entries,
        "GiST R-tree  —  QUERY",
        "Descend ALL consistent nodes",
        ["The query box intersects BOTH MBR A",
         "and MBR B, so GiST descends BOTH",
         "subtrees (thick outlines) -- even",
         "though the two MBRs don't touch.",
         "",
         "One query region can be consistent",
         "with several nodes, so a GiST search",
         "may follow more than one path."],
        show_bbox=True, query=q, visit=visit), 1800)

    add(frame(entries,
        "GiST R-tree  —  QUERY",
        f"Recheck entries -> {len(matched)} match",
        ["Two-step match. The MBR test only",
         "says 'maybe' -- it covers gaps between",
         "entries. So each entry in a visited",
         "node is RECHECKED against the query:",
         "",
         "Green = entry's own box overlaps query.",
         "An entry can sit in a visited MBR yet",
         "still fail (it's in the gap) -> not green.",
         "That recheck is why GiST is 'lossy'.",
         "Pruned nodes were never even looked at."],
        show_bbox=True, query=q, visit=visit, matched=matched), 2200)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gist.gif")
    frames, durs = build_frames()
    durs[-1] = 10000  # pause 10s on the final frame before the loop restarts
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
