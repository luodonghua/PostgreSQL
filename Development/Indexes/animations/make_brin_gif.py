#!/usr/bin/env python3
"""
Animated GIF for a BRIN index:
  Phase 1 (SUMMARIZE): an append-only heap (ordered by date) is divided into
                       page ranges; each range gets a (min,max) summary tuple.
  Phase 2 (QUERY):     a range query compares its bounds to each range's
                       [min,max]; non-overlapping ranges are SKIPPED, overlapping
                       ranges have all their pages bitmap-scanned and rechecked.

Pure-Pillow. Output: brin.gif   Mirrors Development/Indexes/brin.md.
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 440
PANEL_X = 430

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

# append-only heap: 5 page ranges, each with (min_day, max_day)
RANGES = [(1, 3), (3, 6), (6, 9), (9, 12), (12, 15)]
QUERY = (5, 7)   # Jan 5 .. Jan 7


def overlaps(a, b):
    return not (a[1] < b[0] or a[0] > b[1])


def frame(title, subtitle, lines, summarized, query=None, visit=None,
          skip=None, latest=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=(0, 0, 0))
    visit = visit or set()
    skip = skip or set()

    # heap row (ranges) across the top
    hx0, hy = 24, 70
    rw, rh = 76, 44
    gap = 4
    d.text((hx0, hy - 20), "heap (append-only, ordered by day) — page ranges:",
           font=FONT_S, fill=(0, 0, 0))
    for i, (mn, mx) in enumerate(RANGES):
        x = hx0 + i * (rw + gap)
        box = [x, hy, x + rw, hy + rh]
        fill = None
        if i in skip:
            fill = LIGHTGREY
        elif i in visit:
            fill = (213, 245, 227)
        d.rectangle(box, fill=fill, outline=(90, 90, 90))
        d.text((x + 6, hy + 6), f"range {i}", font=FONT_S, fill=(0, 0, 0))
        d.text((x + 6, hy + 24), f"Jan{mn}-{mx}", font=FONT_S, fill=(60, 60, 60))

    # BRIN summaries row below, aligned
    sy = 180
    d.text((hx0, sy - 20), "BRIN index — one (min,max) summary per range:",
           font=FONT_S, fill=(0, 0, 0))
    for i, (mn, mx) in enumerate(RANGES):
        x = hx0 + i * (rw + gap)
        box = [x, sy, x + rw, sy + rh]
        if i < summarized:
            fill = None
            if i in skip:
                fill = LIGHTGREY
            elif i in visit:
                fill = (213, 245, 227)
            elif i == latest:
                fill = (252, 232, 220)
            d.rectangle(box, fill=fill, outline=BLUE, width=2)
            d.text((x + 6, sy + 6), "min max", font=FONT_S, fill=(90, 90, 90))
            d.text((x + 6, sy + 24), f"[{mn},{mx}]", font=FONT_M, fill=(0, 0, 0))
        else:
            d.rectangle(box, outline=(200, 200, 200))
            d.text((x + 10, sy + 14), "(none)", font=FONT_S, fill=(170, 170, 170))
        # link summary -> heap range
        d.line([x + rw / 2, sy, x + rw / 2, hy + rh], fill=(210, 210, 210))

    # query band
    if query is not None:
        d.text((hx0, 250), f"query:  Jan {query[0]} .. Jan {query[1]}",
               font=FONT_M, fill=ORANGE)
        # draw which summaries overlap
        for i, (mn, mx) in enumerate(RANGES):
            x = hx0 + i * (rw + gap)
            tag = "visit" if i in visit else ("skip" if i in skip else "")
            col = GREEN if i in visit else (GREY if i in skip else (0, 0, 0))
            if tag:
                d.text((x + 20, 272), tag, font=FONT_S, fill=col)

    # panel
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 24
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 17

    # legend
    ly = H - 60
    d.rectangle([PANEL_X, ly, PANEL_X + 12, ly + 12], fill=(213, 245, 227),
                outline=(90, 90, 90))
    d.text((PANEL_X + 18, ly - 1), "range scanned (overlaps)", font=FONT_S,
           fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 18, PANEL_X + 12, ly + 30], fill=LIGHTGREY,
                outline=(90, 90, 90))
    d.text((PANEL_X + 18, ly + 17), "range skipped (pruned)", font=FONT_S,
           fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3000):
        frames.append(im); durs.append(ms)

    add(frame("BRIN  —  SUMMARIZE", "Summarize page ranges",
              ["A huge table ordered by day.",
               "BRIN does NOT index every row.",
               "It divides the heap into page",
               "ranges and stores one tiny",
               "(min,max) summary per range."],
              summarized=0))

    for i in range(len(RANGES)):
        add(frame("BRIN  —  SUMMARIZE",
                  f"Summarize range {i}  ->  [{RANGES[i][0]},{RANGES[i][1]}]",
                  ["Scan the range's pages once,",
                   "record the min and max value.",
                   "",
                   "The whole index is just a handful",
                   "of these summaries -- orders of",
                   "magnitude smaller than a B-tree."],
                  summarized=i + 1, latest=i))

    # QUERY
    q = QUERY
    visit = {i for i, r in enumerate(RANGES) if overlaps(r, q)}
    skip = set(range(len(RANGES))) - visit
    add(frame("BRIN  —  QUERY", f"Query Jan {q[0]} .. Jan {q[1]}",
              ["Compare the query bounds to each",
               "range's [min,max].",
               "",
               "Overlap? -> scan that range's pages.",
               "No overlap? -> SKIP the whole range",
               "without reading its heap pages."],
              summarized=len(RANGES), query=q, visit=visit, skip=skip))
    add(frame("BRIN  —  QUERY", f"Scan {len(visit)} range(s), recheck rows",
              ["Only overlapping ranges (green) are",
               "bitmap-scanned; the rest (grey) are",
               "pruned.",
               "",
               "BRIN is lossy: it returns PAGES, so",
               "a Bitmap Heap Scan rechecks each",
               "row against the query to drop",
               "false positives."],
              summarized=len(RANGES), query=q, visit=visit, skip=skip), 10000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "brin.gif")
    frames, durs = build_frames()
    durs[-1] = 10000
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
