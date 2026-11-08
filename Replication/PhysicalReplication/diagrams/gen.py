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


if __name__ == "__main__":
    for name, (fn, size) in DIAGRAMS.items():
        nodes, edges = fn()
        engine.drawio(name, nodes, edges, size)
        engine.svg(name, nodes, edges, size)
        print("wrote", name)
