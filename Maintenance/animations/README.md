# Maintenance animations

Animated GIFs that visualize PostgreSQL's maintenance machinery — **VACUUM**,
**freezing / XID wraparound**, **ANALYZE**, and **autovacuum** table/database
selection — plus the pure-Python (Pillow only) scripts that generate them.

| Animation | What it shows |
|-----------|---------------|
| ![VACUUM](vacuum.gif) | VACUUM's three phases: scan the heap and collect dead TIDs, delete the matching index entries, then free the heap line pointers; trailing empty pages may be truncated. |
| ![Freeze](freeze.gif) | Freezing on the circular 32-bit XID clock: the unfrozen span grows as "now" advances; VACUUM freezes old tuples and advances `relfrozenxid`; `autovacuum_freeze_max_age` forces an anti-wraparound vacuum. |
| ![ANALYZE](analyze.gif) | Two-stage sampling (block sampler → Vitter reservoir) producing `n_distinct`, a most-common-values list, and a histogram in `pg_statistic`. |
| ![Autovacuum tables](autovacuum_tables.gif) | How a worker picks tables: `dead_tuples` vs. the size-scaled threshold per table, then prioritizing by score (wraparound first). |
| ![Autovacuum databases](autovacuum_db.gif) | The launcher/worker model: how one launcher picks a **database** (oldest `datfrozenxid` under wraparound risk, else stalest), and how workers run concurrently under a shared cost budget. |

See the detailed docs: [../vacuum.md](../vacuum.md) ·
[../analyze.md](../analyze.md) · [../autovacuum.md](../autovacuum.md) ·
[../parameters.md](../parameters.md)

## Regenerating

Requires only Python 3 with Pillow (no matplotlib / ffmpeg):

```sh
python3 make_vacuum_gif.py            # writes vacuum.gif
python3 make_freeze_gif.py            # writes freeze.gif
python3 make_analyze_gif.py           # writes analyze.gif
python3 make_autovacuum_tables_gif.py # writes autovacuum_tables.gif
python3 make_autovacuum_db_gif.py     # writes autovacuum_db.gif
```

Each script contains a small, real model of the mechanism — a tiny heap with
line pointers, a TID store, and an index for VACUUM; a circular XID space for
freezing; a block sampler plus Vitter reservoir for ANALYZE; the actual
`vacuum_threshold + scale_factor * reltuples` formula and the launcher's
database-priority rules for autovacuum — so the frames reflect the real
algorithm rather than hand-drawn mock-ups. The behavior is grounded in the
PostgreSQL source (`access/heap/vacuumlazy.c`, `commands/analyze.c`,
`commands/vacuum.c`, `postmaster/autovacuum.c`). Edit the data constants at the
top of each script to change the example.
