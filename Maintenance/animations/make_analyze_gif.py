#!/usr/bin/env python3
"""
Animated GIF for ANALYZE: how PostgreSQL builds planner statistics.

Grounded in src/backend/commands/analyze.c:
  - targrows = 300 * statistics_target  (default target 100 -> 30,000 rows),
    with a floor of 100. The same sample serves every column.
  - Two-stage sampling: a block-level sampler picks which pages to read, then
    Vitter's reservoir algorithm (algorithm Z) keeps a uniform random sample of
    rows from those blocks WITHOUT knowing the total row count in advance.
  - From the sample, per-column stats are written to pg_statistic:
    null_frac, n_distinct, most-common values (MCV) + their frequencies,
    a histogram of the remaining values, and physical/logical correlation.

The animation: a big table of pages -> a handful of sampled pages -> a reservoir
of sampled rows -> the derived MCV list + histogram.

Output: analyze.gif
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

W, H = 705, 520
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

random.seed(42)

GRID_COLS, GRID_ROWS = 16, 8          # 128 "pages"
N_PAGES = GRID_COLS * GRID_ROWS
SAMPLE_PAGES = sorted(random.sample(range(N_PAGES), 18))

# a skewed value distribution to make MCV + histogram meaningful
POP = ([1] * 40 + [2] * 25 + [3] * 12 + list(range(4, 40)) * 1) * 3
RESERVOIR_SIZE = 24


def draw_grid(d, gx, gy, sampled=None, reading=None):
    sampled = set(sampled or [])
    cell = 18
    d.text((gx, gy - 18), f"heap: {N_PAGES} pages (stage 1: pick pages to read)",
           font=FONT_S, fill=DARK)
    for i in range(N_PAGES):
        c = i % GRID_COLS
        r = i // GRID_COLS
        x = gx + c * cell
        y = gy + r * cell
        box = [x, y, x + cell - 2, y + cell - 2]
        if i == reading:
            d.rectangle(box, fill=ORANGE, outline=(120, 90, 0))
        elif i in sampled:
            d.rectangle(box, fill=(213, 245, 227), outline=GREEN)
        else:
            d.rectangle(box, fill=LIGHTGREY, outline=(210, 210, 210))


def draw_reservoir(d, rx, ry, rows, cap=RESERVOIR_SIZE, replaced=None):
    d.text((rx, ry - 18),
           f"reservoir sample (stage 2: Vitter keeps {cap} uniform rows)",
           font=FONT_S, fill=DARK)
    per = 12
    for i in range(cap):
        c = i % per
        r = i // per
        x = rx + c * 34
        y = ry + r * 22
        box = [x, y, x + 30, y + 18]
        if i < len(rows):
            fill = (252, 232, 220) if i == replaced else (213, 229, 245)
            d.rectangle(box, fill=fill, outline=BLUE)
            d.text((x + 7, y + 2), str(rows[i]), font=FONT_S, fill=(40, 40, 40))
        else:
            d.rectangle(box, outline=(210, 210, 210))


def draw_stats(d, sx, sy, mcv, hist, ndistinct):
    d.text((sx, sy - 18), "pg_statistic (per column):", font=FONT_S, fill=DARK)
    d.text((sx, sy), f"n_distinct \u2248 {ndistinct}", font=FONT_S, fill=DARK)
    d.text((sx, sy + 18), "MCV (most common values):", font=FONT_S, fill=DARK)
    bx = sx
    for i, (val, freq) in enumerate(mcv):
        bw = int(60 * freq)
        y = sy + 36 + i * 18
        d.rectangle([bx + 24, y, bx + 24 + max(bw, 2), y + 12], fill=ORANGE,
                    outline=(150, 100, 0))
        d.text((bx, y), f"{val}", font=FONT_S, fill=DARK)
        d.text((bx + 24 + max(bw, 2) + 4, y), f"{freq*100:.0f}%", font=FONT_S,
               fill=(90, 90, 90))
    hy = sy + 36 + len(mcv) * 18 + 10
    d.text((sx, hy), "histogram (remaining values, equal-count buckets):",
           font=FONT_S, fill=DARK)
    maxh = max(hist) if hist else 1
    base = hy + 18 + 34
    for i, hcount in enumerate(hist):
        x = sx + i * 20
        bh = int(34 * hcount / maxh)
        d.rectangle([x, base - bh, x + 16, base], fill=BLUE,
                    outline=(30, 90, 130))
    d.line([sx, base + 1, sx + len(hist) * 20, base + 1], fill=(150, 150, 150))
    d.text((sx, base + 4), "low  <-- value range -->  high",
           font=FONT_S, fill=(120, 120, 120))


def compute_stats(rows):
    from collections import Counter
    c = Counter(rows)
    total = len(rows)
    common = c.most_common(3)
    mcv = [(v, n / total) for v, n in common]
    mcv_vals = {v for v, _ in common}
    rest = sorted(v for v in rows if v not in mcv_vals)
    # 8 equal-count histogram buckets
    nb = 8
    hist = [0] * nb
    if rest:
        for idx, _v in enumerate(rest):
            b = min(nb - 1, idx * nb // len(rest))
            hist[b] += 1
    ndistinct = len(c)
    return mcv, hist, ndistinct


def _wrap(text, font, max_w):
    """Greedy word-wrap `text` so each line fits within max_w pixels."""
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if font.getbbox(trial)[2] <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def _draw_panel(d, subtitle, lines, px=PANEL_X, y=44):
    """Render the subtitle wrapped to roughly the body-text column width, so the
    bold header never sticks out wider than the paragraph beneath it."""
    body_w = max((FONT_S.getbbox(ln)[2] for ln in lines), default=200)
    wrap_w = max(body_w, 150)          # don't wrap narrower than ~150px
    for sl in _wrap(subtitle, FONT_B, wrap_w):
        d.text((px, y), sl, font=FONT_B, fill=DARK)
        y += 20
    y += 6
    for ln in lines:
        d.text((px, y), ln, font=FONT_S, fill=(40, 40, 40))
        y += 16


def frame(title, subtitle, lines, sampled=None, reading=None, reservoir=None,
          replaced=None, stats=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=DARK)
    draw_grid(d, 24, 60, sampled, reading)
    if reservoir is not None:
        draw_reservoir(d, 24, 240, reservoir, replaced=replaced)
    if stats is not None:
        mcv, hist, ndistinct = stats
        draw_stats(d, 24, 330, mcv, hist, ndistinct)

    _draw_panel(d, subtitle, lines)
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3200):
        frames.append(im)
        durs.append(ms)

    add(frame("ANALYZE  —  why", "The planner needs a cheap model of the data",
              ["The query planner chooses plans using",
               "estimates: how many rows match, how",
               "many distinct values, how skewed.",
               "",
               "It cannot read the whole table every",
               "time, so ANALYZE builds a small",
               "statistical SAMPLE and stores summary",
               "statistics in pg_statistic.",
               "",
               "Sample size = 300 x statistics_target.",
               "Default target 100 -> ~30,000 rows,",
               "regardless of whether the table has",
               "1 million or 1 billion rows."]), 4600)

    # Stage 1: pick pages
    add(frame("ANALYZE  —  stage 1: block sampler",
              "Pick a random set of PAGES to read",
              ["First choose which disk pages to",
               "read, using a uniform random block",
               "sampler.",
               "",
               "Reading whole pages (not scattered",
               "rows) keeps I/O sequential-ish and",
               "cheap.",
               "",
               "Green = pages chosen for the sample."],
              sampled=SAMPLE_PAGES), 4200)

    # Stage 2: reservoir fills then replaces
    reservoir = []
    read_order = list(SAMPLE_PAGES)
    rid = 0
    for n, pg in enumerate(read_order):
        # pull a couple rows from this page out of the skewed population
        for _ in range(3):
            val = POP[(rid * 7 + pg) % len(POP)]
            rid += 1
            if len(reservoir) < RESERVOIR_SIZE:
                reservoir.append(val)
                replaced = len(reservoir) - 1
            else:
                # Vitter: replace a random slot with decreasing probability
                j = random.randint(0, rid)
                if j < RESERVOIR_SIZE:
                    reservoir[j] = val
                    replaced = j
                else:
                    replaced = None
        if n in (0, 4, 9, len(read_order) - 1):
            phase = ("fill the reservoir" if len(reservoir) < RESERVOIR_SIZE
                     else "replace at random")
            add(frame("ANALYZE  —  stage 2: reservoir sampling",
                      f"Read sampled pages; {phase}",
                      ["Vitter's reservoir algorithm keeps a",
                       "uniform random sample of rows while",
                       "reading, WITHOUT knowing the total",
                       "row count ahead of time.",
                       "",
                       "- while the reservoir has room, keep",
                       "  every row",
                       "- once full, each new row may replace",
                       "  a random existing one, with",
                       "  probability that falls as more rows",
                       "  are seen",
                       "",
                       "Result: every row had an equal chance",
                       "of being in the final sample."],
                      sampled=SAMPLE_PAGES, reading=pg, reservoir=reservoir,
                      replaced=replaced), 3400)

    # Compute + show stats
    stats = compute_stats(reservoir)
    add(frame("ANALYZE  —  derive statistics",
              "Summaries written to pg_statistic",
              ["From the finished sample, compute per",
               "column and store in pg_statistic:",
               "",
               "- null_frac: fraction of NULLs",
               "- n_distinct: number of distinct",
               "  values (scaled to the table)",
               "- MCV: the most common values and",
               "  their frequencies (captures skew)",
               "- histogram: equal-frequency buckets",
               "  over the remaining values (captures",
               "  range selectivity)",
               "- correlation: physical vs logical",
               "  order (helps index-scan costing)."],
              sampled=SAMPLE_PAGES, reservoir=reservoir, stats=stats), 5000)

    add(frame("ANALYZE  —  how the planner uses it",
              "MCV + histogram -> row estimates",
              ["col = 1  -> look up MCV: ~most common,",
               "            high selectivity estimate",
               "col < 20 -> sum histogram buckets below",
               "            20 for a range estimate",
               "GROUP BY -> n_distinct estimates the",
               "            number of groups",
               "",
               "Raise statistics_target (per column via",
               "ALTER TABLE ... SET STATISTICS) for",
               "skewed or large columns: bigger sample,",
               "more MCV/histogram entries, better",
               "estimates -- at the cost of a slower",
               "ANALYZE."],
              sampled=SAMPLE_PAGES, reservoir=reservoir, stats=stats), 8000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "analyze.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
