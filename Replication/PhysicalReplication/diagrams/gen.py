#!/usr/bin/env python3
"""Physical-replication diagrams. Reuses the drawing engine of
../../LogicalReplication/diagrams/gen.py and writes <name>.drawio + <name>.svg here.

Run:  python3 gen.py
"""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, "..", "..", "LogicalReplication", "diagrams", "gen.py")
spec = importlib.util.spec_from_file_location("engine", ENGINE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.HERE = HERE  # write output next to this script

DIAGRAMS = {}


def diagram(name, size):
    def deco(fn):
        DIAGRAMS[name] = (fn, size)
        return fn
    return deco


@diagram("streaming-architecture", (1000, 440))
def _():
    nodes = [
        ("P", 20, 20, 420, 400, "Primary", "group"),
        ("S", 580, 20, 400, 400, "Standby (standby.signal)", "group"),
        ("bk", 40, 60, 170, 50, "Backends\ncommit", "pub"),
        ("wb", 40, 170, 170, 50, "WAL buffers", "wal"),
        ("wal", 40, 280, 170, 50, "pg_wal/\nsegments", "wal"),
        ("ww", 250, 170, 170, 50, "walwriter /\nbackend flush", "proc"),
        ("ws", 250, 280, 170, 60, "walsender\n(reads WAL, sends)", "proc"),
        ("slot", 250, 365, 170, 40, "physical slot (optional)", "slot"),
        ("swal", 600, 170, 170, 50, "pg_wal/\n(standby copy)", "wal"),
        ("st", 830, 170, 140, 50, "startup process\nreplays WAL", "proc"),
        ("wr", 600, 280, 170, 60, "walreceiver\n(writes + fsyncs)", "proc"),
        ("dat", 830, 280, 140, 60, "data files\n(hot standby reads)", "sub"),
    ]
    edges = [("bk", "wb", "", False), ("wb", "ww", "", False), ("ww", "wal", "fsync", False),
             ("wal", "ws", "", False), ("ws", "wr", "WAL stream (TCP)", False),
             ("wr", "ws", "status reply", True), ("wr", "swal", "write+flush", False),
             ("swal", "st", "", False), ("st", "dat", "redo", False), ("slot", "ws", "", True)]
    return nodes, edges


@diagram("lsn-lag", (940, 220))
def _():
    nodes = [
        ("a", 20, 70, 170, 70, "pg_current_wal_lsn\n(primary wrote)", "wal"),
        ("b", 230, 70, 170, 70, "sent_lsn\n(walsender sent)", "proc"),
        ("c", 440, 70, 170, 70, "write_lsn\n(standby OS received)", "slot"),
        ("d", 650, 70, 120, 70, "flush_lsn\n(standby fsync)", "slot"),
        ("e", 800, 70, 120, 70, "replay_lsn\n(visible to queries)", "sub"),
    ]
    edges = [("a", "b", "", False), ("b", "c", "", False), ("c", "d", "", False), ("d", "e", "", False)]
    return nodes, edges


@diagram("timeline-fork", (1060, 330))
def _():
    nodes = [
        ("a", 20, 110, 200, 70, "Timeline 1\nshared history\n(until last common point)", "wal"),
        ("f", 300, 110, 190, 70, "Divergence point\nold primary dies;\nstandby promoted", "slot"),
        ("n", 620, 30, 410, 70, "Timeline 2 - NEW primary\nnew writes go here (00000002.history)", "sub"),
        ("o", 620, 140, 410, 70, "Timeline 1 - OLD primary kept writing\nunreplicated / divergent changes", "pub"),
        ("r", 620, 250, 410, 55, "pg_rewind: undo divergent blocks,\ncopy from TL2, then follow TL2", "proc"),
    ]
    edges = [("a", "f", "", False), ("f", "n", "promote", False), ("f", "o", "still running", True),
             ("o", "r", "", True)]
    return nodes, edges


@diagram("synchronous-commit", (1010, 300))
def _():
    nodes = [
        ("a", 20, 40, 160, 70, "client\nCOMMIT", "pub"),
        ("b", 220, 40, 160, 70, "primary\nlocal WAL flush\n(always first)", "wal"),
        ("c", 420, 40, 160, 70, "walsender sends\nWAL to standby\n(wait starts)", "proc"),
        ("d", 620, 40, 160, 70, "standby\nacknowledges", "slot"),
        ("e", 820, 40, 160, 70, "client gets OK", "pub"),
        ("w", 300, 190, 210, 70, "remote_write\nstandby received + wrote\n(OS cache)", "slot"),
        ("o", 540, 190, 210, 70, "on (default)\nstandby flushed (fsync)", "slot"),
        ("r", 780, 190, 210, 70, "remote_apply\nstandby replayed\n(visible to queries)", "sub"),
    ]
    edges = [("a", "b", "", False), ("b", "c", "", False), ("c", "d", "", False), ("d", "e", "", False),
             ("d", "w", "", True), ("d", "o", "synchronous_commit\ndecides which ack", True), ("d", "r", "", True)]
    return nodes, edges
@diagram("lock-replay", (1000, 430))
def _():
    nodes = [
        ("p", 20, 20, 290, 90, "Primary\nALTER TABLE / DROP / TRUNCATE /\nLOCK / VACUUM truncation\ntakes ACCESS EXCLUSIVE", "pub"),
        ("w", 370, 20, 220, 90, "WAL\nlock record + the change", "wal"),
        ("s", 690, 20, 290, 90, "Standby startup process\nreplays the lock record,\nneeds ACCESS EXCLUSIVE on the table", "proc"),
        ("d", 340, 170, 320, 80, "Does a standby query hold a lock\non the table?\n(any SELECT holds ACCESS SHARE)", "slot"),
        ("n", 20, 310, 290, 90, "No\nlock granted,\nchange replayed", "sub"),
        ("y", 355, 310, 290, 90, "Yes, but it finishes within\nmax_standby_streaming_delay\nreplay continues", "sub"),
        ("c", 690, 310, 290, 90, "Yes, still running after the delay\nquery cancelled, confl_lock + 1\n(delay = -1: replay waits, lag grows)", "slot"),
    ]
    edges = [("p", "w", "writes", False), ("w", "s", "streamed", False), ("s", "d", "", False),
             ("d", "n", "no query", False), ("d", "y", "short query", False), ("d", "c", "long query", False)]
    return nodes, edges
@diagram("old-primary-loop", (1000, 560))
def _():
    nodes = [
        ("a", 20, 20, 290, 90, "1. Old primary starts as standby\nstandby.signal + primary_conninfo\npointing at the new primary", "pub"),
        ("b", 355, 20, 290, 90, "2. walreceiver connects\nlearns the primary is on timeline 2\nfetches 00000002.history", "proc"),
        ("c", 690, 20, 290, 90, "3. asks for timeline 1 WAL from the\nstart of its segment (0/3000000)\nstarted streaming WAL ... timeline 1", "proc"),
        ("d", 690, 170, 290, 90, "4. new primary: timeline 1 ends at the\nfork point (from the history file)\nEnd of WAL reached on timeline 1", "wal"),
        ("e", 355, 170, 290, 90, "5. startup process decides whether\nto follow timeline 2: compares the\nfork point with its recovery point", "slot"),
        ("f", 690, 330, 290, 90, "fork point >= recovery point\nno WAL beyond the fork\nnew target timeline is 2: it streams\nfrom the new primary, normal standby", "sub"),
        ("g", 355, 330, 290, 90, "fork point < recovery point\nnew timeline 2 forked off ... before\ncurrent recovery point (extra local WAL)", "slot"),
        ("h", 20, 330, 290, 90, "6. automatic retry after 5 s\nstartup process is still on timeline 1,\nso it requests timeline 1 again", "proc"),
        ("i", 355, 460, 290, 70, "Operator action, not automatic:\npg_rewind or re-clone (pg_basebackup)", "sub"),
    ]
    edges = [("a", "b", "", False), ("b", "c", "", False), ("c", "d", "", False), ("d", "e", "", False),
             ("e", "f", "yes", False), ("e", "g", "no", False), ("g", "h", "retry", False),
             ("h", "b", "loops", True), ("g", "i", "you must act", True)]
    return nodes, edges
@diagram("pg-rewind-flow", (1000, 560))
def _():
    nodes = [
        ("a", 20, 20, 290, 90, "1. Find the fork point\ncompare the timeline histories\nof the old and new primary", "pub"),
        ("b", 355, 20, 290, 90, "2. Find the last common checkpoint\nbefore the fork point,\nin the old primary's WAL", "wal"),
        ("c", 690, 20, 290, 90, "3. Read the old primary's own WAL\nfrom that checkpoint to its end;\nnote every block it touched", "proc"),
        ("d", 690, 170, 290, 90, "4. Compare file lists\nnew primary vs old primary,\ndecide an action per file", "proc"),
        ("e", 355, 170, 290, 90, "5. Copy from the new primary:\nthe noted blocks, size fixes,\nother files, WAL from the fork on", "slot"),
        ("f", 20, 170, 290, 90, "6. Write backup_label (start =\nlast common checkpoint) and set\nminRecoveryPoint = new primary's WAL end", "wal"),
        ("g", 20, 320, 290, 90, "7. Start the old primary:\nit replays the new primary's WAL\nfrom the checkpoint, then streams", "sub"),
        ("n1", 355, 320, 290, 90, "Changed on the OLD primary\nafter the fork (known from step 3):\noverwritten by the copy", "slot"),
        ("n2", 20, 460, 290, 80, "Changed on the NEW primary\nafter the fork: applied by the\nWAL replay in step 7", "sub"),
    ]
    edges = [("a", "b", "", False), ("b", "c", "", False), ("c", "d", "", False), ("d", "e", "", False),
             ("e", "f", "", False), ("f", "g", "", False), ("e", "n1", "", True), ("g", "n2", "", True)]
    return nodes, edges
if __name__ == "__main__":
    for name, (fn, size) in DIAGRAMS.items():
        nodes, edges = fn()
        engine.drawio(name, nodes, edges, size)
        engine.svg(name, nodes, edges, size)
        print("wrote", name)
