#!/usr/bin/env python3
"""
Animated GIF for VACUUM's three phases (lazy vacuum).

Mirrors Development/Indexes conventions: pure Pillow, a right-hand text panel,
a small real-ish model of the heap/index/TID-store driving the frames.

Model (grounded in src/backend/access/heap/vacuumlazy.c header):
  Phase I   scan heap pages, prune (incl. HOT), freeze, collect dead TIDs
            into a TID store; set visibility-map bits for all-visible pages.
  Phase II  index vacuuming: delete index entries that point at the dead TIDs.
  Phase III reap the dead line pointers in the heap, freeing space (FSM).
            May then truncate empty trailing pages; update pg_class stats.

Output: vacuum.gif
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 695, 460
PANEL_X = 450

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
    FONT_M = ImageFont.truetype("DejaVuSans.ttf", 12)
except Exception:
    FONT_B = FONT_S = FONT_M = ImageFont.load_default()

GREEN = (39, 174, 96)
ORANGE = (243, 156, 18)
RED = (192, 57, 43)
GREY = (150, 150, 150)
LIGHTGREY = (238, 238, 238)
BLUE = (41, 128, 185)
DARK = (0, 0, 0)

# A tiny heap: 4 pages, each holds up to 4 line pointers (slots).
# tuple states: 'live', 'dead' (deleted/old version), 'frozen', None (empty slot)
# Each tuple carries a key used to show the matching index entry.
HEAP0 = [
    [("live", 10), ("dead", 11), ("live", 12), ("dead", 13)],
    [("dead", 20), ("dead", 21), ("live", 22), (None, None)],
    [("live", 30), ("live", 31), ("dead", 32), ("live", 33)],
    [("dead", 40), ("dead", 41), ("dead", 42), ("dead", 43)],  # becomes empty
]

PAGE_W, PAGE_H = 96, 92
SLOT_H = 18


def heap_dead_tids(heap):
    tids = []
    for p, page in enumerate(heap):
        for s, (st, key) in enumerate(page):
            if st == "dead":
                tids.append((p, s, key))
    return tids


def draw_heap(d, heap, hx, hy, highlight_page=None, reaped=None,
              frozen_set=None, vm_bits=None, truncated=None):
    reaped = reaped or set()
    frozen_set = frozen_set or set()
    vm_bits = vm_bits or {}
    d.text((hx, hy - 20), "heap pages (line pointers -> tuples):",
           font=FONT_S, fill=DARK)
    for p, page in enumerate(heap):
        x = hx + p * (PAGE_W + 8)
        if truncated is not None and p >= truncated:
            d.rectangle([x, hy, x + PAGE_W, hy + PAGE_H], outline=(210, 210, 210))
            d.text((x + 10, hy + 34), "truncated", font=FONT_S, fill=GREY)
            continue
        outline = ORANGE if p == highlight_page else (120, 120, 120)
        wd = 3 if p == highlight_page else 1
        d.rectangle([x, hy, x + PAGE_W, hy + PAGE_H], outline=outline, width=wd)
        d.text((x + 4, hy - 0 + 1), f"page {p}", font=FONT_S, fill=(90, 90, 90))
        for s, (st, key) in enumerate(page):
            sy = hy + 16 + s * SLOT_H
            box = [x + 4, sy, x + PAGE_W - 4, sy + SLOT_H - 2]
            if st is None:
                d.rectangle(box, outline=(210, 210, 210))
                continue
            if (p, s) in reaped:
                d.rectangle(box, fill=LIGHTGREY, outline=(200, 200, 200))
                d.text((x + 8, sy + 2), "free", font=FONT_S, fill=GREY)
                continue
            if (p, s) in frozen_set or st == "frozen":
                fill = (214, 234, 248)  # light blue = frozen
                lab = f"frz {key}"
                col = BLUE
            elif st == "dead":
                fill = (250, 219, 216)  # light red = dead
                lab = f"dead {key}"
                col = RED
            else:
                fill = (213, 245, 227)  # light green = live
                lab = f"live {key}"
                col = GREEN
            d.rectangle(box, fill=fill, outline=col)
            d.text((x + 8, sy + 2), lab, font=FONT_S, fill=(40, 40, 40))
        # visibility-map bits under the page
        if p in vm_bits:
            av, af = vm_bits[p]
            tag = []
            if av:
                tag.append("all-vis")
            if af:
                tag.append("all-frz")
            d.text((x + 2, hy + PAGE_H + 2), " ".join(tag) or "-",
                   font=FONT_S, fill=BLUE if tag else GREY)


def draw_index(d, heap, ix, iy, deleted_keys=None):
    """One B-tree-ish index: one entry per non-empty tuple key."""
    deleted_keys = deleted_keys or set()
    d.text((ix, iy - 18), "index entries (key -> TID):", font=FONT_S, fill=DARK)
    keys = []
    for p, page in enumerate(heap):
        for s, (st, key) in enumerate(page):
            if key is not None:
                keys.append((key, st, p, s))
    keys.sort()
    col_w = 70
    per_row = 6
    for i, (key, st, p, s) in enumerate(keys):
        col = i % per_row
        row = i // per_row
        x = ix + col * col_w
        y = iy + row * 22
        box = [x, y, x + col_w - 6, y + 18]
        if key in deleted_keys:
            d.rectangle(box, fill=LIGHTGREY, outline=(200, 200, 200))
            d.text((x + 4, y + 2), f"x{key}", font=FONT_S, fill=GREY)
        else:
            d.rectangle(box, outline=BLUE)
            d.text((x + 4, y + 2), f"{key}", font=FONT_S, fill=(40, 40, 40))


def _wrap(text, font, max_w):
    """Greedy word-wrap `text` so each line fits within max_w pixels."""
    words = text.split()
    out, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if font.getbbox(trial)[2] <= max_w or not cur:
            cur = trial
        else:
            out.append(cur)
            cur = w
    if cur:
        out.append(cur)
    return out


def _draw_panel(d, subtitle, lines, px=PANEL_X, y=44):
    """Wrap the bold subtitle to the body-text column width so the header never
    sticks out wider than the paragraph beneath it."""
    body_w = max((FONT_S.getbbox(ln)[2] for ln in lines), default=200)
    wrap_w = max(body_w, 150)
    for sl in _wrap(subtitle, FONT_B, wrap_w):
        d.text((px, y), sl, font=FONT_B, fill=DARK)
        y += 20
    y += 6
    for ln in lines:
        d.text((px, y), ln, font=FONT_S, fill=(40, 40, 40))
        y += 16


def frame(title, subtitle, lines, heap, highlight_page=None, reaped=None,
          frozen_set=None, vm_bits=None, deleted_keys=None, tidstore=None,
          truncated=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=DARK)

    draw_heap(d, heap, 24, 60, highlight_page, reaped, frozen_set, vm_bits,
              truncated)
    draw_index(d, heap, 24, 210, deleted_keys)

    # TID store box
    ty = 300
    d.text((24, ty), "TID store (dead tuples found in phase I):",
           font=FONT_S, fill=DARK)
    if tidstore:
        txt = "  ".join(f"({p},{s})" for (p, s, _k) in tidstore)
    else:
        txt = "(empty)"
    d.rectangle([24, ty + 16, 420, ty + 40], outline=RED if tidstore else GREY)
    d.text((30, ty + 20), txt, font=FONT_S,
           fill=RED if tidstore else GREY)

    # panel
    _draw_panel(d, subtitle, lines)

    # legend
    ly = H - 86
    def chip(yy, color, label):
        d.rectangle([PANEL_X, yy, PANEL_X + 12, yy + 12], fill=color,
                    outline=(90, 90, 90))
        d.text((PANEL_X + 18, yy - 1), label, font=FONT_S, fill=(40, 40, 40))
    chip(ly, (213, 245, 227), "live tuple")
    chip(ly + 16, (250, 219, 216), "dead tuple (reclaimable)")
    chip(ly + 32, (214, 234, 248), "frozen tuple")
    chip(ly + 48, LIGHTGREY, "freed / deleted")
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3200):
        frames.append(im)
        durs.append(ms)

    heap = [list(p) for p in HEAP0]

    # Intro
    add(frame("VACUUM  —  the problem", "MVCC leaves dead tuples behind",
              ["UPDATE and DELETE do not erase rows.",
               "They leave the OLD row version in",
               "place, marked dead, so other",
               "snapshots can still see it.",
               "",
               "Dead tuples (red) accumulate as",
               "bloat and still have INDEX entries",
               "pointing at them.",
               "",
               "VACUUM reclaims that space in three",
               "phases."],
              heap), 4200)

    # Phase I: scan pages, collect dead TIDs, freeze some, set VM bits
    tidstore = []
    frozen_set = set()
    vm_bits = {}
    for p in range(len(heap)):
        page_dead = [(p, s, k) for s, (st, k) in enumerate(heap[p])
                     if st == "dead"]
        tidstore = tidstore + page_dead
        # freeze old live tuples on fully scanned pages (illustrative)
        if p == 2:
            frozen_set.add((2, 0))
        # a page with no dead tuples and all-visible gets VM bits
        allvis = all(st != "dead" for st, _ in heap[p])
        if allvis:
            allfrz = any((p, s) in frozen_set for s in range(len(heap[p])))
            vm_bits[p] = (True, allfrz)
        add(frame("VACUUM  —  Phase I: scan heap",
                  f"Scan page {p}: prune, freeze, record dead TIDs",
                  ["Walk the heap page by page.",
                   "",
                   "- prune HOT chains & dead tuples,",
                   "  turning dead row versions into",
                   "  reclaimable free line pointers",
                   "- freeze very old live tuples",
                   "- remember each dead tuple's TID",
                   "  in the TID store",
                   "- if a page has only all-visible",
                   "  tuples, set its visibility-map",
                   "  bit (lets index-only scans and",
                   "  future vacuums skip it)."],
                  heap, highlight_page=p, frozen_set=frozen_set,
                  vm_bits=vm_bits, tidstore=tidstore))

    dead_keys = {k for (_p, _s, k) in tidstore}

    # Phase II: index vacuuming
    add(frame("VACUUM  —  Phase II: index vacuuming",
              "Delete index entries that point at dead TIDs",
              ["Now that every dead TID is known,",
               "scan each index and delete the",
               "entries that reference those TIDs.",
               "",
               "This must happen BEFORE the heap",
               "slots are freed -- otherwise a slot",
               "could be reused by a new row while",
               "a stale index entry still points at",
               "it.",
               "",
               "(Skipped if the table has no indexes",
               "or the wraparound failsafe fired.)"],
              heap, frozen_set=frozen_set, vm_bits=vm_bits,
              deleted_keys=dead_keys, tidstore=tidstore), 4600)

    # Phase III: reap dead line pointers
    reaped = {(p, s) for (p, s, _k) in tidstore}
    for (p, s, _k) in tidstore:
        heap[p][s] = (None, None)
    add(frame("VACUUM  —  Phase III: reap heap",
              "Free the dead line pointers; update the FSM",
              ["Revisit the pages in the TID store",
               "and turn each dead line pointer into",
               "free space.",
               "",
               "The free-space map (FSM) is updated",
               "so future INSERT/UPDATE can reuse",
               "the space.",
               "",
               "Space is reused in place -- the file",
               "usually does NOT shrink."],
              heap, reaped=reaped, frozen_set=frozen_set, vm_bits=vm_bits,
              deleted_keys=dead_keys), 4600)

    # Truncation: page 3 is now entirely empty at the tail
    tail_empty = all(st is None for st, _ in heap[-1])
    trunc = len(heap) - 1 if tail_empty else None
    add(frame("VACUUM  —  finish: maybe truncate",
              "Trailing empty pages go back to the OS",
              ["If whole pages at the END of the",
               "table are now empty, VACUUM can",
               "truncate them and give the disk",
               "space back (needs a brief exclusive",
               "lock).",
               "",
               "Finally it updates pg_class",
               "(relpages, reltuples, relfrozenxid)",
               "and the cumulative statistics so the",
               "planner and autovacuum see fresh",
               "numbers."],
              heap, frozen_set=frozen_set, vm_bits=vm_bits,
              truncated=trunc), 8000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vacuum.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
