#!/usr/bin/env python3
"""Generate each diagram twice from one definition:
   <name>.drawio  - editable in diagrams.net / draw.io
   <name>.svg     - renders inline in markdown

Run:  python3 gen.py        (rewrites every diagram in this folder)

Node:  (id, x, y, w, h, label, kind)   kind -> colour (see KINDS)
Edge:  (src, dst, label, dashed)
Label lines are separated by '\n'.
"""
import math
import os
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))

KINDS = {  # fill, stroke
    "pub":   ("#dae8fc", "#6c8ebf"),   # publisher side
    "sub":   ("#d5e8d4", "#82b366"),   # subscriber side
    "wal":   ("#fff2cc", "#d6b656"),   # WAL / storage
    "slot":  ("#f8cecc", "#b85450"),   # slots / state that must be watched
    "proc":  ("#e1d5e7", "#9673a6"),   # background processes
    "plain": ("#f5f5f5", "#666666"),
    "group": ("#ffffff", "#999999"),   # container
}


def drawio(name, nodes, edges, size):
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    for nid, x, y, w, h, label, kind in nodes:
        fill, stroke = KINDS[kind]
        if kind == "group":
            style = (f"rounded=1;whiteSpace=wrap;html=1;fillColor=none;strokeColor={stroke};"
                     "dashed=1;verticalAlign=top;fontStyle=1;")
        else:
            style = (f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};"
                     f"strokeColor={stroke};")
        val = escape(label).replace("\n", "&lt;br&gt;")
        cells.append(f'<mxCell id="{nid}" value="{val}" style="{style}" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    for i, (s, d, label, dashed) in enumerate(edges):
        style = ("endArrow=block;html=1;rounded=0;edgeStyle=orthogonalEdgeStyle;"
                 + ("dashed=1;" if dashed else ""))
        cells.append(f'<mxCell id="e{i}" value="{escape(label)}" style="{style}" edge="1" '
                     f'parent="1" source="{s}" target="{d}"><mxGeometry relative="1" as="geometry"/></mxCell>')
    xml = ('<mxfile host="app.diagrams.net"><diagram name="%s"><mxGraphModel dx="1000" dy="600" '
           'grid="1" gridSize="10" page="1" pageWidth="%d" pageHeight="%d"><root>%s</root>'
           '</mxGraphModel></diagram></mxfile>' % (name, size[0], size[1], "".join(cells)))
    with open(os.path.join(HERE, name + ".drawio"), "w") as f:
        f.write(xml)


def svg(name, nodes, edges, size):
    by = {n[0]: n for n in nodes}
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size[0]} {size[1]}" '
           f'width="{size[0]}" height="{size[1]}" font-family="Helvetica,Arial,sans-serif" font-size="12">',
           '<defs><marker id="a" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
           '<path d="M0,0 L10,4 L0,8 z" fill="#333"/></marker></defs>',
           f'<rect width="{size[0]}" height="{size[1]}" fill="white"/>']
    for nid, x, y, w, h, label, kind in nodes:  # containers first (drawn underneath)
        if kind != "group":
            continue
        fill, stroke = KINDS[kind]
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="none" '
                   f'stroke="{stroke}" stroke-dasharray="6 4"/>')
        out.append(f'<text x="{x + w / 2}" y="{y + 16}" text-anchor="middle" font-weight="bold">'
                   f'{escape(label)}</text>')

    def anchor(a, b):
        ax, ay = a[1] + a[3] / 2, a[2] + a[4] / 2
        bx, by_ = b[1] + b[3] / 2, b[2] + b[4] / 2
        dx, dy = bx - ax, by_ - ay

        def edge(n, ddx, ddy):  # point where the centre-to-centre line leaves node n
            sx = (n[3] / 2) / abs(ddx) if ddx else 1e9
            sy = (n[4] / 2) / abs(ddy) if ddy else 1e9
            s = min(sx, sy)
            return n[1] + n[3] / 2 + ddx * s, n[2] + n[4] / 2 + ddy * s
        return edge(a, dx, dy), edge(b, -dx, -dy)

    pairs = {(e[0], e[1]) for e in edges}
    for s, d, label, dashed in edges:
        (x1, y1), (x2, y2) = anchor(by[s], by[d])
        side = 0
        if (d, s) in pairs:                       # opposite edge exists: draw the two lines apart
            side = 1 if s < d else -1
            L = math.hypot(x2 - x1, y2 - y1) or 1
            ox, oy = -(y2 - y1) / L * 9 * side, (x2 - x1) / L * 9 * side
            x1, y1, x2, y2 = x1 + ox, y1 + oy, x2 + ox, y2 + oy
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        out.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="#333" '
                   f'stroke-width="1.5"{dash} marker-end="url(#a)"/>')
        if label:
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            lw = 6.6 * max(len(t) for t in label.split("\n"))   # estimated text width
            lh = 15 * len(label.split("\n"))
            box = (mx - lw / 2, my - lh, mx + lw / 2, my + 4)
            for n in nodes:
                if n[6] == "group":
                    continue
                if box[0] < n[1] + n[3] and box[2] > n[1] and box[1] < n[2] + n[4] and box[3] > n[2]:
                    print(f"  WARNING [{name}] label '{label}' overlaps box '{n[0]}'")
            need = lh if abs(x2 - x1) < abs(y2 - y1) else lw       # vertical edge: height matters, else width
            if need > math.hypot(x2 - x1, y2 - y1) - 8:
                print(f"  WARNING [{name}] label '{label}' does not fit its gap ({need:.0f}px needed vs {math.hypot(x2-x1,y2-y1):.0f}px)")
            ty = my - 4 if side >= 0 else my + 16
            out.append(f'<text x="{mx:.0f}" y="{ty:.0f}" text-anchor="middle" fill="#333" '
                       f'stroke="white" stroke-width="3" paint-order="stroke">{escape(label)}</text>')
    for nid, x, y, w, h, label, kind in nodes:
        if kind == "group":
            continue
        fill, stroke = KINDS[kind]
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}"/>')
        lines = label.split("\n")
        y0 = y + h / 2 - (len(lines) - 1) * 8 + 4
        for i, ln in enumerate(lines):
            wt = ' font-weight="bold"' if i == 0 and len(lines) > 1 else ""
            out.append(f'<text x="{x + w / 2}" y="{y0 + i * 16:.0f}" text-anchor="middle"{wt}>{escape(ln)}</text>')
    out.append("</svg>")
    with open(os.path.join(HERE, name + ".svg"), "w") as f:
        f.write("\n".join(out))


DIAGRAMS = {}


def diagram(name, size):
    def deco(fn):
        DIAGRAMS[name] = (fn, size)
        return fn
    return deco


# --------------------------------------------------------------------------
@diagram("architecture", (1140, 460))
def _():
    nodes = [
        ("P", 20, 20, 500, 420, "Publisher (wal_level = logical)", "group"),
        ("S", 620, 20, 500, 420, "Subscriber", "group"),
        ("bk", 40, 60, 180, 50, "Backend\nINSERT/UPDATE/DELETE", "pub"),
        ("wal", 40, 190, 180, 50, "WAL\n(+ logical info)", "wal"),
        ("pubn", 40, 330, 180, 60, "Publication\n(what to send)", "pub"),
        ("ws", 330, 190, 170, 60, "walsender\n(decode + pgoutput)", "proc"),
        ("slot", 330, 330, 170, 70, "Replication slot\nrestart_lsn\nconfirmed_flush_lsn", "slot"),
        ("lau", 640, 60, 180, 50, "Launcher", "proc"),
        ("aw", 640, 190, 180, 60, "Apply worker\n(1 per subscription)", "proc"),
        ("tsw", 920, 190, 180, 60, "Tablesync worker\n(initial copy)", "proc"),
        ("tbl", 640, 330, 180, 50, "Subscriber tables", "sub"),
        ("orig", 920, 330, 180, 60, "Replication origin\n(progress LSN)", "slot"),
    ]
    edges = [
        ("bk", "wal", "writes", False),
        ("wal", "ws", "reads", False),
        ("ws", "slot", "advances", True),
        ("pubn", "ws", "filters", True),
        ("ws", "aw", "stream (protocol)", False),
        ("lau", "aw", "starts", True),
        ("aw", "tsw", "spawns", True),
        ("aw", "tbl", "applies", False),
        ("aw", "orig", "records", True),
    ]
    return nodes, edges


# --------------------------------------------------------------------------
@diagram("slot-lsns", (1100, 300))
def _():
    nodes = [
        ("old", 20, 90, 170, 70, "Recyclable WAL\n(older than restart_lsn)", "plain"),
        ("r", 300, 90, 190, 70, "restart_lsn\noldest WAL the slot may\nstill need to re-decode", "slot"),
        ("c", 590, 90, 190, 70, "confirmed_flush_lsn\nsubscriber has durably\napplied up to here", "slot"),
        ("n", 880, 90, 190, 70, "pg_current_wal_lsn()\nnewest WAL written", "wal"),
        ("g", 285, 30, 515, 150, "Kept on disk by the slot", "group"),
        ("x", 300, 225, 190, 50, "catalog_xmin: oldest\ncatalog row version pinned", "slot"),
    ]
    edges = [("old", "r", "", False), ("r", "c", "", False), ("c", "n", "lag = n - c", False),
             ("r", "x", "also pins", True)]
    return nodes, edges


# --------------------------------------------------------------------------
@diagram("decoding-pipeline", (1240, 340))
def _():
    nodes = [
        ("wal", 20, 40, 120, 60, "WAL on disk\n(wal_level=logical)", "wal"),
        ("rd", 190, 40, 130, 60, "XLogReader\nreads from slot's\nrestart_lsn", "proc"),
        ("dec", 400, 40, 140, 60, "decode.c\nper-rmgr dispatch\n(Heap, Xact, Standby)", "proc"),
        ("rb", 690, 40, 140, 60, "ReorderBuffer\nqueue changes per xid;\nspill / stream", "slot"),
        ("pl", 910, 40, 120, 60, "Output plugin\npgoutput /\ntest_decoding", "pub"),
        ("ws", 1080, 40, 120, 60, "walsender\nsends bytes", "proc"),
        ("cat", 400, 200, 140, 70, "System catalogs\n(old row versions\nkept by catalog_xmin)", "wal"),
        ("sb", 690, 200, 140, 60, "SnapBuild\ncatalog snapshot\nfor each commit", "slot"),
        ("sub", 1080, 200, 120, 60, "Apply worker\non subscriber", "sub"),
    ]
    edges = [("wal", "rd", "", False), ("rd", "dec", "records", False),
             ("dec", "rb", "changes + commits", False), ("sb", "rb", "snapshot", True),
             ("cat", "sb", "", True), ("dec", "sb", "running xacts", True),
             ("rb", "pl", "on COMMIT", False), ("pl", "ws", "", False), ("ws", "sub", "", False)]
    return nodes, edges


# --------------------------------------------------------------------------
@diagram("tablesync-states", (940, 250))
def _():
    nodes = [
        ("i", 20, 60, 130, 60, "i  init\nqueued; worker\nnot started", "plain"),
        ("d", 190, 60, 150, 60, "d  data copy\ntemp slot + snapshot,\nCOPY running", "proc"),
        ("f", 380, 60, 150, 60, "f  finished copy\n(then in-memory w, c:\nsync catches up to apply)", "slot"),
        ("s", 570, 60, 150, 60, "s  sync done\nsync worker exits; apply\nwatches until that LSN", "pub"),
        ("r", 760, 60, 150, 60, "r  ready\nnormal replication;\ntemp slot dropped", "sub"),
        ("n", 190, 160, 340, 60, "Changes that commit during the copy are streamed from the\ntemp slot's start LSN and applied by the tablesync worker\nafter COPY (this is why no write is lost or doubled)", "wal"),
    ]
    edges = [("i", "d", "", False), ("d", "f", "", False), ("f", "s", "", False), ("s", "r", "", False),
             ("d", "n", "", True)]
    return nodes, edges


# --------------------------------------------------------------------------
@diagram("failover-slot-sync", (1300, 400))
def _():
    nodes = [
        ("P", 20, 20, 300, 340, "Primary", "group"),
        ("S", 520, 20, 300, 340, "Physical standby", "group"),
        ("U", 1020, 20, 240, 340, "Subscriber", "group"),
        ("ls", 40, 60, 260, 60, "Logical slot s\nfailover = true", "slot"),
        ("ps", 40, 170, 260, 60, "Physical slot sb1\n(feeds the standby)", "slot"),
        ("cfg", 40, 280, 260, 60, "synchronized_standby_slots='sb1'\n(logical walsender waits for sb1)", "pub"),
        ("sw", 540, 60, 260, 60, "slotsync worker\nsync_replication_slots = on", "proc"),
        ("ss", 540, 170, 260, 60, "Slot s (synced = true)\ncopy of restart/confirmed LSN", "slot"),
        ("wr", 540, 280, 260, 60, "walreceiver\nprimary_slot_name = sb1\nprimary_conninfo has dbname=", "proc"),
        ("aw", 1040, 60, 200, 60, "Apply worker\nsubscription failover=true", "sub"),
        ("alt", 1040, 190, 200, 90, "After promotion:\nALTER SUBSCRIPTION\n... CONNECTION (new host)", "plain"),
    ]
    edges = [("ps", "wr", "WAL", False), ("ls", "sw", "slot position (polled)", True),
             ("sw", "ss", "creates/updates", False), ("aw", "alt", "repoint", True),
             ("ss", "alt", "takes over", True)]
    return nodes, edges


# --------------------------------------------------------------------------
@diagram("troubleshooting-tree", (1600, 800))
def _():
    nodes = [
        ("root", 600, 20, 320, 50, "Subscriber is behind / not changing", "slot"),
        ("q1", 600, 120, 320, 50, "Publisher: is the slot active?\n(pg_replication_slots.active)", "proc"),
        ("q2", 160, 240, 330, 50, "Subscriber: is the subscription enabled?\n(pg_subscription.subenabled)", "proc"),
        ("q3", 980, 240, 320, 50, "Is replay_lsn advancing?\n(sample twice)", "proc"),
        ("a1", 20, 370, 250, 80, "disable_on_error was hit\nread the subscriber log,\nfix the cause, then ENABLE", "sub"),
        ("a2", 330, 370, 290, 80, "Worker not running\nlog shows connection errors:\npg_hba, password, network,\nmax_wal_senders, slots in use", "sub"),
        ("a3", 790, 370, 240, 80, "Just slow\ncompare apply speed with\nthe publisher write rate\n(topic 11)", "sub"),
        ("q4", 1140, 370, 330, 50, "Subscriber: what is the apply\nworker doing? (pg_stat_activity)", "proc"),
        ("a7", 860, 520, 180, 90, "Idle (LogicalApplyMain)\nbut sent > replay:\nnetwork or\nwal_sender_timeout", "sub"),
        ("a4", 1060, 520, 190, 90, "wait_event = Lock\nfind the blocker in\npg_locks, resolve it", "sub"),
        ("a5", 1270, 520, 170, 90, "Restarting / ERROR\nread the error\n(topic 12 table)", "sub"),
        ("a6", 1460, 520, 130, 90, "100 % CPU on one\nhuge transaction:\nwait; streaming\n(topic 07, 11)", "sub"),
        ("b1", 20, 650, 230, 40, "CREATE SUBSCRIPTION hangs", "slot"),
        ("b1a", 20, 720, 230, 60, "Old open transaction on the\npublisher; slot creation\nwaits (topic 06)", "sub"),
        ("b2", 290, 650, 230, 40, "Table stuck in 'd' or 'i'", "slot"),
        ("b2a", 290, 720, 230, 60, "Topic 10 'What goes wrong':\nworker limits, copy errors,\ntablesync slot waiting", "sub"),
        ("b3", 560, 650, 230, 40, "Publisher disk filling", "slot"),
        ("b3a", 560, 720, 230, 60, "Find the inactive / lagging\nslot; fix the subscriber or\ndrop it (topic 05)", "sub"),
        ("b4", 830, 650, 230, 40, "Rows differ between sides", "slot"),
        ("b4a", 830, 720, 230, 60, "confl_* counters, log (12);\ncompare checksums, then\nrepair or re-sync a table", "sub"),
    ]
    edges = [
        ("root", "q1", "", False),
        ("q1", "q2", "NO", False), ("q1", "q3", "YES", False),
        ("q2", "a1", "disabled", False), ("q2", "a2", "enabled", False),
        ("q3", "a3", "YES", False), ("q3", "q4", "NO", False),
        ("q4", "a7", "Idle", False), ("q4", "a4", "Lock", False),
        ("q4", "a5", "Error", False), ("q4", "a6", "CPU", False),
        ("b1", "b1a", "", False), ("b2", "b2a", "", False), ("b3", "b3a", "", False), ("b4", "b4a", "", False),
    ]
    return nodes, edges


# --------------------------------------------------------------------------
if __name__ == "__main__":
    for name, (fn, size) in DIAGRAMS.items():
        nodes, edges = fn()
        drawio(name, nodes, edges, size)
        svg(name, nodes, edges, size)
        print("wrote", name)
