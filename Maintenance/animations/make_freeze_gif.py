#!/usr/bin/env python3
"""
Animated GIF for FREEZE and transaction-ID (XID) wraparound.

Why freeze exists (grounded in vacuum.c / vacuumlazy.c and the XID design):
  - Every row stores the XID that inserted it (xmin). Visibility is decided by
    comparing XIDs on a 32-bit *circular* number line (~4.2B values). "Older"
    means "roughly 2B behind the current XID".
  - As the current XID advances, a very old live row could appear to be "in the
    future" once the counter wraps -> the row would vanish. To prevent this,
    VACUUM FREEZE stamps old-enough live tuples as frozen (always visible),
    and advances the table's relfrozenxid (the oldest unfrozen XID).
  - vacuum_freeze_min_age: how old a tuple must be to get frozen.
    autovacuum_freeze_max_age: age of relfrozenxid that forces an
    anti-wraparound autovacuum, even on an otherwise-idle table.

The animation shows a circular XID clock with the current XID advancing, the
"frozen horizon" (relfrozenxid), the freeze_min_age band, and the
autovacuum_freeze_max_age danger line triggering an anti-wraparound vacuum.

Output: freeze.gif
"""
import os
import math
from PIL import Image, ImageDraw, ImageFont

W, H = 700, 460
PANEL_X = 430

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

CX, CY, R = 215, 225, 150

# scaled-down model of the 2^32 XID space
XID_SPACE = 360          # degrees == whole circle == ~4.2B real XIDs
FREEZE_MIN_AGE = 50      # vacuum_freeze_min_age (deg)  (real default 50M)
FREEZE_MAX_AGE = 200     # autovacuum_freeze_max_age (deg) (real default 200M)


def ang_to_xy(deg, r):
    # 0 deg at top, clockwise
    a = math.radians(deg - 90)
    return (CX + r * math.cos(a), CY + r * math.sin(a))


def draw_clock(d, cur, relfrozen, show_minage=False, show_maxage=False,
               danger=False):
    # circle
    d.ellipse([CX - R, CY - R, CX + R, CY + R], outline=(120, 120, 120), width=2)
    d.text((CX - 70, CY - R - 26), "32-bit XID space (circular)",
           font=FONT_S, fill=DARK)
    # tick marks
    for deg in range(0, 360, 30):
        p1 = ang_to_xy(deg, R)
        p2 = ang_to_xy(deg, R - 8)
        d.line([p1, p2], fill=(200, 200, 200))

    # frozen region: from relfrozen back ~half the circle is "past" (safe)
    # draw the band between relfrozenxid and current XID as "live, unfrozen"
    # arc of live tuples (relfrozen .. cur)
    start = relfrozen
    extent = (cur - relfrozen) % 360
    # live/unfrozen arc (green)
    _draw_arc(d, start, extent, R - 4, GREEN, 10)
    # frozen arc (everything else, blue) -- the safe, always-visible past
    _draw_arc(d, cur, 360 - extent, R - 4, BLUE, 6)

    # freeze_min_age band just behind current xid
    if show_minage:
        _draw_arc(d, (cur - FREEZE_MIN_AGE) % 360, FREEZE_MIN_AGE, R - 20,
                  ORANGE, 4)
        mp = ang_to_xy((cur - FREEZE_MIN_AGE / 2) % 360, R - 40)
        d.text((mp[0] - 30, mp[1]), "freeze_min_age", font=FONT_S, fill=ORANGE)

    # danger line at freeze_max_age behind current
    if show_maxage:
        dp = ang_to_xy((cur - FREEZE_MAX_AGE) % 360, R)
        dp2 = ang_to_xy((cur - FREEZE_MAX_AGE) % 360, R - 30)
        d.line([dp, dp2], fill=RED, width=3)
        d.text((dp[0] - 40, dp[1] + 6), "freeze_max_age", font=FONT_S, fill=RED)

    # current XID hand
    cp = ang_to_xy(cur, R - 12)
    d.line([(CX, CY), cp], fill=RED if danger else DARK, width=3)
    d.ellipse([CX - 4, CY - 4, CX + 4, CY + 4], fill=DARK)
    lp = ang_to_xy(cur, R + 14)
    d.text((lp[0] - 14, lp[1] - 6), "now", font=FONT_S, fill=RED if danger else DARK)

    # relfrozenxid marker
    rp = ang_to_xy(relfrozen, R + 10)
    d.ellipse([rp[0] - 4, rp[1] - 4, rp[0] + 4, rp[1] + 4], fill=BLUE)
    d.text((rp[0] - 24, rp[1] + 4), "relfrozenxid", font=FONT_S, fill=BLUE)


def _draw_arc(d, start_deg, extent_deg, r, color, width):
    # PIL arc uses standard math angles with 0 at 3 o'clock, CCW positive.
    # our deg: 0 at top, clockwise. Convert: pil = deg - 90.
    a0 = start_deg - 90
    a1 = start_deg + extent_deg - 90
    bbox = [CX - r, CY - r, CX + r, CY + r]
    d.arc(bbox, a0, a1, fill=color, width=width)


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


def frame(title, subtitle, lines, cur, relfrozen, show_minage=False,
          show_maxage=False, danger=False, age_val=None):
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, font=FONT_B, fill=DARK)
    draw_clock(d, cur, relfrozen, show_minage, show_maxage, danger)

    if age_val is not None:
        d.text((CX - 60, CY + R + 30),
               f"age(relfrozenxid) = now - relfrozenxid \u2248 {age_val}",
               font=FONT_S, fill=RED if danger else DARK)

    _draw_panel(d, subtitle, lines)

    # legend
    ly = H - 70
    def chip(yy, color, label):
        d.rectangle([PANEL_X, yy, PANEL_X + 12, yy + 12], fill=color,
                    outline=(90, 90, 90))
        d.text((PANEL_X + 18, yy - 1), label, font=FONT_S, fill=(40, 40, 40))
    chip(ly, GREEN, "live, not yet frozen")
    chip(ly + 16, BLUE, "frozen (always visible)")
    chip(ly + 32, RED, "wraparound danger line")
    return im


def build_frames():
    frames, durs = [], []

    def add(im, ms=3400):
        frames.append(im)
        durs.append(ms)

    cur = 60
    relfrozen = 10

    add(frame("FREEZE  —  why", "Visibility is decided on a circular clock",
              ["Each row records the XID that",
               "inserted it (xmin). PostgreSQL",
               "compares XIDs on a 32-bit circular",
               "number line of ~4.2 billion values.",
               "",
               "'Older' = roughly 2 billion XIDs",
               "behind 'now'. If a very old live row",
               "were left alone, the advancing",
               "counter would eventually make it",
               "look like it is in the FUTURE -- and",
               "the row would silently disappear."],
              cur, relfrozen), 4600)

    # advance current xid; gap grows
    for cur in (90, 130, 170):
        add(frame("FREEZE  —  the gap grows",
                  "As transactions run, 'now' advances",
                  ["The green arc is the span of live",
                   "tuples that are still unfrozen --",
                   "from relfrozenxid up to now.",
                   "",
                   "Every committed transaction pushes",
                   "'now' forward. Without freezing,",
                   "this unfrozen span keeps growing",
                   "toward the dangerous half-circle."],
                  cur, relfrozen, age_val=f"{(cur-relfrozen)}"))

    # show freeze_min_age band
    add(frame("FREEZE  —  vacuum_freeze_min_age",
              "VACUUM freezes tuples older than freeze_min_age",
              ["When VACUUM scans a page, any live",
               "tuple older than vacuum_freeze_min_age",
               "is FROZEN: stamped as unconditionally",
               "visible, so its original XID no longer",
               "matters.",
               "",
               "Freezing lets VACUUM advance",
               "relfrozenxid -- the oldest XID that is",
               "still unfrozen in this table."],
              170, relfrozen, show_minage=True, age_val=f"{170-relfrozen}"))

    # vacuum advances relfrozenxid
    for rf in (60, 110):
        add(frame("FREEZE  —  relfrozenxid advances",
                  "Freezing shrinks the unfrozen span",
                  ["After freezing the old tuples, VACUUM",
                   "moves relfrozenxid forward (blue",
                   "marker). The blue 'frozen past' arc",
                   "grows; the green unfrozen arc",
                   "shrinks.",
                   "",
                   "This is the whole point of freezing:",
                   "keep age(relfrozenxid) safely small."],
                  170, rf, show_minage=True, age_val=f"{170-rf}"))

    # danger: relfrozenxid falls far behind -> anti-wraparound
    add(frame("FREEZE  —  anti-wraparound trigger",
              "autovacuum_freeze_max_age forces a vacuum",
              ["If a table is never vacuumed (e.g.",
               "insert-only or autovacuum disabled),",
               "relfrozenxid falls far behind.",
               "",
               "Once age(relfrozenxid) reaches",
               "autovacuum_freeze_max_age, autovacuum",
               "launches an ANTI-WRAPAROUND vacuum on",
               "the table -- even if autovacuum is",
               "turned off for it. This is not",
               "optional; it protects your data."],
              320, 70, show_maxage=True, danger=True, age_val="200 (= max_age)"))

    add(frame("FREEZE  —  resolved",
              "Anti-wraparound vacuum fixes it",
              ["The forced vacuum freezes the old",
               "tuples and advances relfrozenxid, so",
               "age() drops well below max_age and the",
               "danger passes.",
               "",
               "Takeaways:",
               "- freezing is normal, continuous work",
               "- never disable autovacuum globally",
               "- watch age(relfrozenxid) per table &",
               "  datfrozenxid per database."],
              320, 290, show_maxage=True, age_val="30 (safe)"), 8000)
    return frames, durs


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "freeze.gif")
    frames, durs = build_frames()
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durs, loop=0, optimize=False)
    print(f"wrote {out}  ({len(frames)} frames, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
