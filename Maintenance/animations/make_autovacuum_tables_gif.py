#!/usr/bin/env python3
"""
Animated GIF: how autovacuum decides WHICH TABLES need work, and in what order.

Grounded in relation_needs_vacanalyze() in src/backend/postmaster/autovacuum.c
(PostgreSQL master / 20devel):

  vacthresh   = vacuum_threshold        + vacuum_scale_factor        * reltuples
                (capped at vacuum_max_threshold, if set)
  vacinsthresh= vacuum_insert_threshold + vacuum_insert_scale_factor * reltuples
                                                                * pct_unfrozen
  anlthresh   = analyze_threshold       + analyze_scale_factor       * reltuples

  needs vacuum  if dead_tuples      > vacthresh
  needs ivacuum if ins_since_vacuum > vacinsthresh
  needs analyze if mod_since_analyze> anlthresh
  FORCED (anti-wraparound) if age(relfrozenxid) > autovacuum_freeze_max_age

Newer versions compute a per-table SCORE = max over components of
(value / threshold) * weight, and process the highest-scoring tables first.

Output: autovacuum_tables.gif
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 470
PANEL_X = 470

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

# GUC defaults
VAC_THRESH = 50
VAC_SCALE = 0.20
ANL_THRESH = 50
ANL_SCALE = 0.10
FREEZE_MAX_AGE = 200_000_000

# tables: name, reltuples, dead_tuples, mod_since_analyze, xid_age
TABLES = [
    ("orders",    100_000, 25_000,  5_000,  40_000_000),
    ("customers",  50_000,    400,  9_000,  10_000_000),
    ("audit_log", 500_000, 10_000, 60_000, 210_000_000),  # wraparound!
    ("lookup",      1_000,     20,     10,   5_000_000),
    ("sessions",  200_000, 90_000, 90_000,  30_000_000),
]


def vacthresh(reltuples):
    return VAC_THRESH + VAC_SCALE * reltuples


def anlthresh(reltuples):
    return ANL_THRESH + ANL_SCALE * reltuples


def analyze_table(t):
    name, rel, dead, mod, xid_age = t
    vt = vacthresh(rel)
    at = anlthresh(rel)
    forced = xid_age > FREEZE_MAX_AGE
    needs_vac = dead > vt or forced
    needs_anl = mod > at
    vac_score = dead / vt
    anl_score = mod / at
    xid_score = xid_age / FREEZE_MAX_AGE
    if forced and xid_score > 1.0:
        xid_score = xid_score ** 1.5  # aggressive scaling near wraparound
    score = max(vac_score, anl_score, xid_score)
    return dict(name=name, rel=rel, dead=dead, mod=mod, xid_age=xid_age,
                vt=vt, at=at, forced=forced, needs_vac=needs_vac,
                needs_anl=needs_anl, score=score)


def draw_table_rows(d, x, y, rows, highlight=None, show_score=False,
                    order=None):
    headers = ["table", "n_tuples", "dead", "vac_thresh", "status"]
    cols = [x, x + 92, x + 168, x + 220, x + 300]
    for h, cx in zip(headers, cols):
        d.text((cx, y), h, font=FONT_S, fill=(90, 90, 90))
    seq = order if order is not None else list(range(len(rows)))
    for rank, idx in enumerate(seq):
        r = rows[idx]
        ry = y + 20 + rank * 40
        box = [x - 4, ry - 2, x + 390, ry + 34]
        if highlight == idx:
            d.rectangle(box, fill=(252, 243, 220), outline=ORANGE)
        d.text((cols[0], ry), r["name"], font=FONT_M, fill=DARK)
        d.text((cols[1], ry), f"{r['rel']:,}", font=FONT_S, fill=(60, 60, 60))
        # dead-tuple bar vs threshold
        d.text((cols[2], ry), f"{r['dead']:,}", font=FONT_S, fill=(60, 60, 60))
        d.text((cols[3], ry), f"{r['vt']:,.0f}", font=FONT_S, fill=(60, 60, 60))
        # bar
        bar_x = cols[0]
        bar_y = ry + 16
        bar_w = 280
        frac = min(1.5, r["dead"] / r["vt"]) / 1.5
        d.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 8],
                    outline=(210, 210, 210))
        # threshold line at (1.0 / 1.5) of the bar
        tx = bar_x + int(bar_w * (1.0 / 1.5))
        d.line([tx, bar_y - 2, tx, bar_y + 10], fill=RED)
        col = RED if r["needs_vac"] else GREEN
        d.rectangle([bar_x, bar_y, bar_x + int(bar_w * frac), bar_y + 8],
                    fill=col)
        # status
        st = []
        if r["forced"]:
            st.append("WRAPAROUND!")
        elif r["needs_vac"]:
            st.append("vacuum")
        if r["needs_anl"]:
            st.append("analyze")
        if not st:
            st = ["ok"]
        sc = RED if r["forced"] else (ORANGE if r["needs_vac"] or r["needs_anl"]
                                      else GREEN)
        d.text((cols[4], ry), ",".join(st), font=FONT_S, fill=sc)
        if show_score:
            d.text((cols[4], ry + 14), f"score {r['score']:.2f}", font=FONT_S,
                   fill=BLUE)


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
        y += 15


def frame(title, subtitle, lines, rows, highlight=None, show_score=False,
          order=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=DARK)
    d.text((24, 40),
           f"vac_thresh = {VAC_THRESH} + {VAC_SCALE:g} x n_tuples    "
           f"(red line = threshold)", font=FONT_S, fill=(90, 90, 90))
    draw_table_rows(d, 24, 60, rows, highlight, show_score, order)

    _draw_panel(d, subtitle, lines)
    return im


def build_frames():
    rows = [analyze_table(t) for t in TABLES]
    frames, durs = [], []

    def add(im, ms=3600):
        frames.append(im)
        durs.append(ms)

    add(frame("AUTOVACUUM  —  which tables?",
              "Each table gets a threshold from its size",
              ["Once a worker is connected to a",
               "database, it inspects EVERY table.",
               "",
               "For each table it computes a dead-tuple",
               "threshold that scales with table size:",
               "",
               "  vac_thresh = vacuum_threshold",
               "       + vacuum_scale_factor x n_tuples",
               "",
               "Big tables tolerate more dead tuples",
               "before vacuuming; tiny tables trigger",
               "almost immediately."],
              rows), 4800)

    for idx in range(len(rows)):
        r = rows[idx]
        verdict = ("FORCED anti-wraparound" if r["forced"]
                   else ("needs vacuum" if r["needs_vac"]
                         else "under threshold"))
        add(frame("AUTOVACUUM  —  compare each table",
                  f"{r['name']}: dead {r['dead']:,} vs thresh {r['vt']:,.0f}",
                  ["dead_tuples > vac_thresh ?  -> vacuum",
                   "mod_since_analyze > anl_thresh ?",
                   "                            -> analyze",
                   "age(relfrozenxid) >",
                   "   autovacuum_freeze_max_age ?",
                   "                 -> FORCED vacuum",
                   "",
                   f"verdict: {verdict}.",
                   "",
                   "The red line in each bar is that",
                   "table's own threshold. A bar past the",
                   "line needs vacuuming."],
                  rows, highlight=idx))

    # Scoring / prioritization
    order = sorted(range(len(rows)), key=lambda i: rows[i]["score"],
                   reverse=True)
    add(frame("AUTOVACUUM  —  prioritize by score",
              "Highest score first",
              ["More than one table can be due at once,",
               "but workers are limited.",
               "",
               "Each table gets a SCORE = how far past",
               "its threshold it is (value / threshold),",
               "taking the worst component.",
               "",
               "Tables near XID wraparound get their",
               "score scaled up aggressively, so they",
               "sort to the front.",
               "",
               "audit_log (wraparound) is processed",
               "first, then the rest by score."],
              rows, show_score=True, order=order), 8000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "autovacuum_tables.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
