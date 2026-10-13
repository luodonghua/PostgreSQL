#!/usr/bin/env python3
"""
Generate an animated GIF explaining a GIN (Generalized Inverted Index):
  Phase 1 (INSERT): rows holding composite values (arrays) are inserted one by
                    one. The opclass EXTRACTS the keys from each value, and every
                    key is mapped to a POSTING LIST -- the set of row TIDs that
                    contain it. A key value is stored ONCE no matter how many rows
                    contain it; new rows just append their TID to the key's list.
  Phase 2 (QUERY):  a containment query `tags @> {red, green}` extracts its own
                    query keys, looks each up in the entry tree, and the opclass
                    `consistent(AND)` INTERSECTS the posting lists to get the
                    candidate rows.

Pure-Pillow (no matplotlib). Output: gin.gif

Mirrors Development/Indexes/gin.md:
  - one key stored once, many rows attached (inverted mapping)
  - entry tree of distinct keys + per-key posting lists
  - search = per-key lookup, then `consistent` combines (intersection for @>)
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 440
PANEL_X = 430
DURATION_MS = 3000

# Rows of a single composite column `tags text[]`. Order = insertion order.
ROWS = [
    ("r1", ["red", "blue", "green"]),
    ("r2", ["green"]),
    ("r3", ["red", "green"]),
    ("r4", ["blue"]),
]

# Distinct keys appear top-to-bottom in sorted order (entry tree is sorted).
KEY_ORDER = ["blue", "green", "red"]

# Containment query: rows whose tags contain BOTH of these.
QUERY_KEYS = ["green", "red"]

# colors
COL_KEY = {
    "red":   (192, 57, 43),
    "green": (39, 174, 96),
    "blue":  (41, 128, 185),
}
COL_BOX = (120, 120, 120)
COL_LATEST = (231, 76, 60)
COL_MATCH = (39, 174, 96)
COL_MATCH_FILL = (213, 245, 227)

try:
    FONT_B = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    FONT_S = ImageFont.truetype("DejaVuSans.ttf", 11)
    FONT_M = ImageFont.truetype("DejaVuSans-Bold.ttf", 12)
except Exception:
    FONT_B = FONT_S = FONT_M = ImageFont.load_default()


def posting_lists(rows):
    """Build key -> [tids] in insertion order, preserving appearance order."""
    pl = {}
    for tid, keys in rows:
        for k in keys:
            pl.setdefault(k, [])
            if tid not in pl[k]:
                pl[k].append(tid)
    return pl


def frame(n_inserted, title, subtitle, lines,
          latest_key_tid=None, query_keys=None, lookup=None,
          candidates=None, show_entry_tree=True):
    """
    n_inserted: how many ROWS have been inserted so far (drives posting lists).
    latest_key_tid: (key, tid) just appended -> highlight.
    query_keys: keys being probed (draw query box).
    lookup: set of keys whose posting rows to highlight (lookup phase).
    candidates: set of tids in the final intersection -> green.
    """
    lookup = lookup or set()
    candidates = candidates or set()
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=(0, 0, 0))

    # ---- left: the rows (source composite values) ----
    rx, ry = 20, 44
    d.text((rx, ry), "Rows  (tags text[])", font=FONT_M, fill=(0, 0, 0))
    ry += 20
    for i, (tid, keys) in enumerate(ROWS):
        inserted = i < n_inserted
        box = [rx, ry, rx + 180, ry + 26]
        d.rectangle(box, outline=COL_BOX if inserted else (210, 210, 210), width=1)
        txt = f"{tid}: {{{', '.join(keys)}}}"
        d.text((rx + 6, ry + 6), txt, font=FONT_S,
               fill=(30, 30, 30) if inserted else (200, 200, 200))
        ry += 32

    # arrow label: extract keys
    d.text((rx, ry + 2), "│ extract keys (opclass)", font=FONT_S, fill=(120, 120, 120))
    d.text((rx, ry + 18), "▼", font=FONT_S, fill=(120, 120, 120))

    # ---- middle: the inverted index (entry tree -> posting lists) ----
    if show_entry_tree:
        ex, ey = 20, ry + 36
        d.text((ex, ey), "Inverted index  (key → posting list of TIDs)",
               font=FONT_M, fill=(0, 0, 0))
        ey += 20
        pl = posting_lists(ROWS[:n_inserted])
        for key in KEY_ORDER:
            tids = pl.get(key, [])
            kcol = COL_KEY[key]
            # key cell
            kbox = [ex, ey, ex + 70, ey + 24]
            is_lookup = key in lookup
            d.rectangle(kbox, outline=kcol, width=3 if is_lookup else 1)
            d.text((ex + 8, ey + 5), key, font=FONT_M, fill=kcol)
            d.text((ex + 74, ey + 6), "→", font=FONT_S, fill=(90, 90, 90))
            # posting list cells
            px = ex + 92
            for tid in tids:
                tb = [px, ey, px + 34, ey + 24]
                if tid in candidates and is_lookup:
                    # a final candidate, shown only inside a PROBED key's list
                    d.rectangle(tb, outline=COL_MATCH, width=3)
                    d.rectangle([tb[0]+2, tb[1]+2, tb[2]-2, tb[3]-2],
                                fill=COL_MATCH_FILL)
                    d.text((px + 6, ey + 5), tid, font=FONT_S, fill=(20, 90, 50))
                elif latest_key_tid == (key, tid):
                    d.rectangle(tb, outline=COL_LATEST, width=3)
                    d.text((px + 6, ey + 5), tid, font=FONT_S, fill=COL_LATEST)
                elif is_lookup:
                    d.rectangle(tb, outline=kcol, width=2)
                    d.text((px + 6, ey + 5), tid, font=FONT_S, fill=(40, 40, 40))
                else:
                    d.rectangle(tb, outline=(170, 170, 170), width=1)
                    d.text((px + 6, ey + 5), tid, font=FONT_S, fill=(90, 90, 90))
                px += 40
            ey += 32

    # ---- query box ----
    if query_keys is not None:
        qx, qy = 20, H - 42
        d.rectangle([qx, qy, qx + 300, qy + 28], outline=(243, 156, 18), width=3)
        d.text((qx + 8, qy + 7),
               f"query:  tags @> {{{', '.join(query_keys)}}}",
               font=FONT_M, fill=(176, 108, 0))

    # ---- right panel ----
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 26
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 18

    # legend
    ly = H - 104
    d.rectangle([PANEL_X, ly, PANEL_X + 12, ly + 12], outline=COL_LATEST, width=2)
    d.text((PANEL_X + 18, ly - 1), "just appended TID", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 18, PANEL_X + 12, ly + 30], outline=(90, 90, 90), width=2)
    d.text((PANEL_X + 18, ly + 17), "key being probed", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 36, PANEL_X + 12, ly + 48], outline=COL_MATCH, width=2)
    d.text((PANEL_X + 18, ly + 35), "candidate (match)", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 54, PANEL_X + 12, ly + 66], outline=(243, 156, 18), width=2)
    d.text((PANEL_X + 18, ly + 53), "query", font=FONT_S, fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms):
        frames.append(im); durs.append(ms)

    # intro
    add(frame(0,
        "GIN  —  INSERT (build the inverted index)",
        "One key, stored once",
        ["GIN indexes COMPOSITE values that",
         "hold many keys (arrays, jsonb,",
         "tsvector).",
         "",
         "The opclass EXTRACTS each key and",
         "maps it to a POSTING LIST: the set",
         "of row TIDs that contain that key.",
         "",
         "A key is stored ONCE; extra rows just",
         "append their TID to the list."]), 2600)

    # Phase 1: insert each row, highlighting the appended TIDs
    for i, (tid, keys) in enumerate(ROWS, 1):
        # one frame per key appended, so the fan-out is visible
        for k in keys:
            add(frame(i,
                "GIN  —  INSERT (build the inverted index)",
                f"Insert {tid}  —  key '{k}'",
                [f"Row {tid} = {{{', '.join(keys)}}}.",
                 "",
                 f"Append {tid} to key '{k}'s posting",
                 "list. If '{}' already exists as a key,".replace("{}", k),
                 "no new key is created — the TID is",
                 "just added to the existing list.",
                 "",
                 "That is the inverted mapping:",
                 "key → {rows containing it}."],
                latest_key_tid=(k, tid)), 1000)

    # settle
    add(frame(len(ROWS),
        "GIN  —  INSERT (build the inverted index)",
        "Entry tree + posting lists",
        ["The distinct keys form a sorted",
         "ENTRY TREE (a B-tree of keys).",
         "",
         "Each key points to its posting list.",
         "Small lists live inline (compressed",
         "varbyte deltas); huge ones spill to a",
         "separate POSTING TREE keyed by TID.",
         "",
         "'green' is in 3 rows but stored once."]), 2400)

    # Phase 2: query arrives
    q = QUERY_KEYS
    add(frame(len(ROWS),
        "GIN  —  QUERY  (tags @> {green, red})",
        "Extract the query keys",
        ["Containment query: which rows contain",
         "BOTH 'green' AND 'red'?",
         "",
         "The opclass extracts the query keys",
         "{green, red} — the SAME extraction",
         "used at insert time."],
        query_keys=q), 2200)

    # lookup each key's posting list
    add(frame(len(ROWS),
        "GIN  —  QUERY  (tags @> {green, red})",
        "Look up each key",
        ["Probe the entry tree for each query",
         "key and read its posting list:",
         "",
         "  green → {r1, r2, r3}",
         "  red   → {r1, r3}",
         "",
         "Only two probes — non-matching rows",
         "are never touched."],
        query_keys=q, lookup=set(q)), 2400)

    # consistent AND -> intersection
    pl = posting_lists(ROWS)
    cand = set(pl[q[0]])
    for k in q[1:]:
        cand &= set(pl[k])
    add(frame(len(ROWS),
        "GIN  —  QUERY  (tags @> {green, red})",
        f"consistent(AND) → {len(cand)} candidate(s)",
        ["`@>` needs ALL query keys, so the",
         "opclass `consistent` function combines",
         "the lists with AND = INTERSECTION:",
         "",
         "  {r1,r2,r3} ∩ {r1,r3} = {r1, r3}",
         "",
         "r2 has 'green' but not 'red' → dropped.",
         "",
         "Lossy opclasses (e.g. jsonb_path_ops)",
         "then RECHECK each candidate heap row."],
        query_keys=q, lookup=set(q), candidates=cand), 3000)

    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gin.gif")
    frames, durs = build_frames()
    durs[-1] = 10000  # pause 10s on the final frame before the loop restarts
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
