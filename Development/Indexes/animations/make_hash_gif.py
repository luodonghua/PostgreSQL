#!/usr/bin/env python3
"""
Animated GIF for a Hash index:
  Phase 1 (INSERT): values are hashed to a bucket; entries (hash code, ctid)
                    land in buckets; a full bucket gets an OVERFLOW page.
  Phase 2 (SEARCH): a query value is hashed, the bucket located directly, and
                    the bucket scanned for the matching hash code (then a heap
                    recheck, since only the hash code is stored).

Pure-Pillow. Output: hash.gif   Mirrors Development/Indexes/hash.md.
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

BLUE = (41, 128, 185)
GREEN = (39, 174, 96)
RED = (231, 76, 60)
ORANGE = (243, 156, 18)
GREY = (120, 120, 120)

NBUCKETS = 4
CAP = 3  # entries per bucket page before an overflow page is needed

# (value, hashcode) -- hashcode mod 4 chooses the bucket; crafted for a clear demo
ITEMS = [
    ("alice", 0x12),   # bucket 2
    ("bob",   0x05),   # bucket 1
    ("carol", 0x1a),   # bucket 2
    ("dave",  0x07),   # bucket 3
    ("erin",  0x0a),   # bucket 2
    ("frank", 0x16),   # bucket 2  -> overflow in bucket 2
    ("gina",  0x04),   # bucket 0
]
QUERY = ("erin", 0x0a)


def bucket_of(h):
    return h % NBUCKETS


def frame(title, subtitle, lines, buckets, overflow, latest=None,
          qbucket=None, found=None, hash_arrow=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=(0, 0, 0))

    # draw the 4 buckets as columns
    bw, bx0, by0 = 86, 30, 185
    gap = 10
    for b in range(NBUCKETS):
        x = bx0 + b * (bw + gap)
        header = [x, by0 - 26, x + bw, by0 - 6]
        hl = (qbucket == b)
        d.rectangle(header, fill=(214, 234, 248) if hl else (235, 235, 235),
                    outline=(90, 90, 90))
        d.text((x + 10, by0 - 24), f"bucket {b}", font=FONT_S, fill=(0, 0, 0))
        # primary page
        page = [x, by0, x + bw, by0 + 90]
        d.rectangle(page, outline=(RED if hl else (90, 90, 90)),
                    width=3 if hl else 1)
        for i, (val, h) in enumerate(buckets[b][:CAP]):
            yy = by0 + 6 + i * 26
            fill = None
            if (val, h) == latest:
                fill = (252, 232, 220)
            elif found is not None and (val, h) == found:
                fill = (213, 245, 227)
            if fill:
                d.rectangle([x + 3, yy - 2, x + bw - 3, yy + 18], fill=fill)
            d.text((x + 6, yy), f"0x{h:02x} {val}", font=FONT_S, fill=(0, 0, 0))
        # overflow page (if any)
        if overflow[b]:
            oy = by0 + 108
            opage = [x, oy, x + bw, oy + 60]
            d.rectangle(opage, outline=ORANGE, width=2)
            d.text((x + 4, oy - 14), "overflow", font=FONT_S, fill=ORANGE)
            d.line([x + bw / 2, by0 + 90, x + bw / 2, oy], fill=ORANGE, width=1)
            for i, (val, h) in enumerate(overflow[b]):
                yy = oy + 6 + i * 26
                fill = (213, 245, 227) if (found == (val, h)) else None
                if fill:
                    d.rectangle([x + 3, yy - 2, x + bw - 3, yy + 18], fill=fill)
                d.text((x + 6, yy), f"0x{h:02x} {val}", font=FONT_S, fill=(0, 0, 0))

    # hashing arrow / annotation (in the clear band between title and buckets)
    if hash_arrow is not None:
        val, h, b = hash_arrow
        ann = f"hash('{val}') = 0x{h:02x}   ->   0x{h:02x} mod {NBUCKETS} = bucket {b}"
        d.rectangle([18, 120, 18 + 8 + len(ann) * 7, 142],
                    fill=(255, 247, 230), outline=ORANGE)
        d.text((24, 124), ann, font=FONT_M, fill=(0, 0, 0))

    # panel
    y = 44
    d.text((PANEL_X, y), subtitle, font=FONT_B, fill=(0, 0, 0)); y += 24
    for ln in lines:
        d.text((PANEL_X, y), ln, font=FONT_S, fill=(40, 40, 40)); y += 17

    # legend
    ly = H - 60
    d.rectangle([PANEL_X, ly, PANEL_X + 12, ly + 12], outline=ORANGE, width=2)
    d.text((PANEL_X + 18, ly - 1), "overflow page", font=FONT_S, fill=(40, 40, 40))
    d.rectangle([PANEL_X, ly + 18, PANEL_X + 12, ly + 30], fill=(213, 245, 227),
                outline=(90, 90, 90))
    d.text((PANEL_X + 18, ly + 17), "match (then heap recheck)", font=FONT_S,
           fill=(40, 40, 40))
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3000):
        frames.append(im); durs.append(ms)

    buckets = [[] for _ in range(NBUCKETS)]
    overflow = [[] for _ in range(NBUCKETS)]

    add(frame("Hash index  —  INSERT", "Hash the value to a bucket",
              ["Each value is hashed to a 4-byte",
               "code; the code mod (#buckets)",
               "picks the bucket.",
               "",
               "The index stores only the hash",
               "code + ctid, never the value."],
              buckets, overflow))

    for val, h in ITEMS:
        b = bucket_of(h)
        if len(buckets[b]) < CAP:
            buckets[b].append((val, h))
            ov = False
        else:
            overflow[b].append((val, h))
            ov = True
        add(frame("Hash index  —  INSERT",
                  f"Insert '{val}'",
                  ["Hash picks the bucket directly.",
                   ("Bucket full -> entry goes to an"
                    if ov else "Entry stored in the bucket page,"),
                   ("OVERFLOW page chained to it."
                    if ov else "kept sorted by hash code."),
                   "",
                   "No tree, no ordering -- just a",
                   "direct jump to one bucket."],
                  buckets, overflow, latest=(val, h),
                  qbucket=b, hash_arrow=(val, h, b)))

    # SEARCH
    val, h = QUERY
    b = bucket_of(h)
    add(frame("Hash index  —  SEARCH", f"Search '{val}'",
              ["Hash the query value, jump straight",
               "to its bucket -- no descent, no scan",
               "of other buckets.",
               "",
               f"hash('{val}') -> bucket {b}."],
              buckets, overflow, qbucket=b, hash_arrow=(val, h, b)))
    add(frame("Hash index  —  SEARCH", "Scan the bucket, then recheck",
              ["Within the bucket (and its overflow",
               "pages) find entries with a matching",
               "hash code -- binary search per page.",
               "",
               "Only the hash code is stored, so the",
               "heap tuple is RECHECKED to confirm",
               "the real value (collisions possible)."],
              buckets, overflow, qbucket=b, found=(val, h)), 10000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hash.gif")
    frames, durs = build_frames()
    durs[-1] = 10000
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
