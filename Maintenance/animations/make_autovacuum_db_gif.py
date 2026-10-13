#!/usr/bin/env python3
"""
Animated GIF: the autovacuum launcher/worker model and how it picks a DATABASE.

Grounded in do_start_worker() + the launcher main loop in
src/backend/postmaster/autovacuum.c:

  - A single LAUNCHER wakes every autovacuum_naptime (default 60s), divided
    among databases, and starts at most one worker per wakeup.
  - Choosing a database (in priority order):
      1. If ANY database's datfrozenxid is older than
         (nextXid - autovacuum_freeze_max_age), pick the one with the OLDEST
         datfrozenxid -- XID wraparound danger wins over everything.
      2. Else if any datminmxid is past the multixact limit, pick the oldest.
      3. Else pick the database with the OLDEST last-autovacuum time,
         skipping databases with no stats entry and those processed less than
         one naptime ago.
  - Up to autovacuum_max_workers workers run concurrently (across databases).
  - Workers share a cost budget (cost-based delay is balanced among them).

Output: autovacuum_db.gif
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 730, 470
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
PURPLE = (142, 68, 173)
DARK = (0, 0, 0)

FREEZE_MAX_AGE = 200_000_000
MAX_WORKERS = 3

# databases: name, datfrozenxid_age, last_autovac_secs_ago, has_stats
DBS = [
    dict(name="app_prod",  age=40_000_000,  last=120, stats=True),
    dict(name="analytics", age=90_000_000,  last=400, stats=True),
    dict(name="archive",   age=230_000_000, last=5000, stats=True),  # wrap!
    dict(name="scratch",   age=5_000_000,   last=10,  stats=False),  # no stats
    dict(name="reports",   age=20_000_000,  last=800, stats=True),
]


def pick_database(dbs):
    """Returns (index, reason)."""
    wrap = [i for i, d in enumerate(dbs) if d["age"] > FREEZE_MAX_AGE]
    if wrap:
        i = max(wrap, key=lambda j: dbs[j]["age"])
        return i, "wraparound: oldest datfrozenxid"
    cand = [i for i, d in enumerate(dbs) if d["stats"]]
    i = max(cand, key=lambda j: dbs[j]["last"])
    return i, "oldest last-autovacuum time"


def draw_launcher(d, dbs, chosen=None, reason="", worker_dbs=None):
    worker_dbs = worker_dbs or []
    # launcher box (same width as the database boxes below for visual alignment)
    lx, ly, lw = 24, 60, 300
    d.rectangle([lx, ly, lx + lw, ly + 50], outline=PURPLE, width=2)
    d.text((lx + 12, ly + 8), "LAUNCHER", font=FONT_B, fill=PURPLE)
    d.text((lx + 12, ly + 28),
           "one per cluster  \u00b7  wakes every naptime",
           font=FONT_S, fill=(90, 90, 90))

    # databases column
    dbx, dby = 24, 150
    d.text((dbx, dby - 20), "databases in the cluster:", font=FONT_S, fill=DARK)
    for i, db in enumerate(dbs):
        y = dby + i * 52
        box = [dbx, y, dbx + 300, y + 44]
        if i == chosen:
            d.rectangle(box, fill=(252, 243, 220), outline=ORANGE, width=2)
        else:
            d.rectangle(box, outline=(190, 190, 190))
        d.text((dbx + 8, y + 4), db["name"], font=FONT_M, fill=DARK)
        wrap = db["age"] > FREEZE_MAX_AGE
        agecol = RED if wrap else (60, 60, 60)
        d.text((dbx + 8, y + 24),
               f"datfrozenxid age \u2248 {db['age'] // 1_000_000}M",
               font=FONT_S, fill=agecol)
        d.text((dbx + 150, y + 24),
               ("no stats" if not db["stats"]
                else f"last av {db['last']}s ago"),
               font=FONT_S, fill=GREY if not db["stats"] else (60, 60, 60))
        if wrap:
            d.text((dbx + 150, y + 4), "WRAPAROUND RISK", font=FONT_S, fill=RED)
        # worker arrow
        if i in worker_dbs:
            d.text((dbx + 310, y + 14), "<- worker", font=FONT_S, fill=GREEN)
            d.rectangle([dbx + 300, y + 10, dbx + 304, y + 34], fill=GREEN)

    if chosen is not None:
        cy = dby + chosen * 52
        d.line([lx + lw // 2, ly + 50, dbx + 150, cy], fill=ORANGE, width=2)
        d.text((dbx + 320, cy + 2), f"pick: {reason}", font=FONT_S, fill=ORANGE)


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


def frame(title, subtitle, lines, dbs, chosen=None, reason="", worker_dbs=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=DARK)
    draw_launcher(d, dbs, chosen, reason, worker_dbs)

    _draw_panel(d, subtitle, lines)
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3800):
        frames.append(im)
        durs.append(ms)

    add(frame("AUTOVACUUM  —  one launcher, many DBs",
              "A single launcher coordinates everything",
              ["Autovacuum is NOT one process per table.",
               "",
               "A single LAUNCHER wakes up every",
               "autovacuum_naptime (default 60s).",
               "That naptime is divided among the",
               "databases, so a cluster with 6 DBs",
               "gets one wakeup every ~10s.",
               "",
               "On each wakeup it starts at most one",
               "WORKER, after choosing which database",
               "needs attention most."],
              DBS), 5000)

    # Priority 1: wraparound DB
    chosen, reason = pick_database(DBS)
    add(frame("AUTOVACUUM  —  pick a database (1)",
              "XID wraparound danger wins",
              ["Priority 1: is any database's",
               "datfrozenxid older than",
               "(nextXid - autovacuum_freeze_max_age)?",
               "",
               "If so, pick the database with the",
               "OLDEST datfrozenxid, ignoring",
               "everything else.",
               "",
               "'archive' is past the limit (230M >",
               "200M), so it is chosen regardless of",
               "when it was last processed."],
              DBS, chosen=chosen, reason=reason), 5200)

    # Hypothetical: no wraparound -> oldest last-autovac
    dbs2 = [dict(d) for d in DBS]
    dbs2[2]["age"] = 60_000_000  # archive no longer at risk
    chosen2, reason2 = pick_database(dbs2)
    add(frame("AUTOVACUUM  —  pick a database (2)",
              "No wraparound? Pick the stalest DB",
              ["Priority 3 (the common case): no DB is",
               "near wraparound.",
               "",
               "Pick the database with the OLDEST",
               "last-autovacuum time -- the one that",
               "has waited longest.",
               "",
               "Skip databases that have NO stats",
               "entry ('scratch') -- nobody has",
               "connected, so nothing to do -- and",
               "any DB already processed < 1 naptime",
               "ago (avoids double-picking)."],
              dbs2, chosen=chosen2, reason=reason2), 5200)

    # Workers running concurrently
    add(frame("AUTOVACUUM  —  workers",
              f"Up to {MAX_WORKERS} workers at once",
              ["The launcher connects a worker to the",
               "chosen database. The worker then",
               "scans that DB's tables and vacuums",
               "the ones over threshold (previous",
               "animation).",
               "",
               "Several workers run concurrently, up",
               "to autovacuum_max_workers -- possibly",
               "in different databases.",
               "",
               "They SHARE one I/O cost budget: the",
               "cost-delay is balanced across active",
               "workers, so adding workers does not",
               "multiply the I/O impact."],
              DBS, worker_dbs=[0, 1, 2]), 8000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "autovacuum_db.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
