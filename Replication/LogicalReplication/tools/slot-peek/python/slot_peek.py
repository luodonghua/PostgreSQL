#!/usr/bin/env python3
"""slot_peek.py - see what is waiting in a logical replication slot, without consuming it.

Read-only for the slot you inspect:
  * PostgreSQL 12+: changes are read from a TEMPORARY COPY of the slot
    (pg_copy_logical_replication_slot). The original slot and its consumer are untouched,
    so nothing has to be paused. The copy disappears when this program's session ends.
  * PostgreSQL 10/11: no slot copy exists. The slot is peeked directly, which is only
    possible while its consumer is disconnected (see README: "Pausing the consumer").

Decoders:
  pgoutput  Decodes exactly what a native subscriber receives: honours the publications'
            table list, row filters and column lists; knows the replica-identity (key)
            columns. Needs the publication names (auto-detected from an active walsender).
  text      Copies the slot as test_decoding. Works for any plugin (pgoutput, pglogical,
            wal2json, ...), shows ALL tables of the database, no publication filtering.

Usage:
  slot_peek.py overview                         list slots and what to run
  slot_peek.py peek --slot s                    summary + changes (auto decoder)
  slot_peek.py peek --slot s --format sql --since-lsn 0/3000060   replay SQL for unapplied changes
  slot_peek.py position                         (on the SUBSCRIBER) applied position per subscription

Connection: --dsn "host=... port=... dbname=... user=..." or the usual PG* environment
variables. Requires psycopg (3) or psycopg2.
"""
import argparse
import csv
import datetime as dt
import json
import re
import struct
import sys

try:
    import psycopg  # psycopg 3

    def connect(dsn):
        return psycopg.connect(dsn, autocommit=True)
except ImportError:  # pragma: no cover - fallback driver
    try:
        import psycopg2

        def connect(dsn):
            conn = psycopg2.connect(dsn)
            conn.autocommit = True
            return conn
    except ImportError:
        sys.exit("slot_peek.py needs psycopg (3) or psycopg2: pip install 'psycopg[binary]'")

VERSION = "1.0"
PG_EPOCH = dt.datetime(2000, 1, 1, tzinfo=dt.timezone.utc)


# --------------------------------------------------------------------------- helpers
def q(conn, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params)
    rows = cur.fetchall() if cur.description else []
    cur.close()
    return rows


def lsn_int(lsn):
    hi, lo = lsn.split("/")
    return (int(hi, 16) << 32) | int(lo, 16)


def lsn_str(v):
    return "%X/%X" % (v >> 32, v & 0xFFFFFFFF)


def pretty_bytes(n):
    if n is None:
        return "-"
    for unit in ("bytes", "kB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return ("%d %s" % (n, unit)) if unit == "bytes" else ("%.1f %s" % (n, unit))
        n /= 1024.0


def quote_ident(name):
    if re.fullmatch(r"[a-z_][a-z0-9_$]*", name):
        return name
    return '"' + name.replace('"', '""') + '"'


def quote_literal(v):
    return "'" + v.replace("'", "''") + "'"


def fail(msg):
    sys.exit("ERROR: " + msg)


# --------------------------------------------------------------------------- server facts
def server_info(conn):
    (num,) = q(conn, "SELECT current_setting('server_version_num')::int")[0]
    (ver,) = q(conn, "SELECT current_setting('server_version')")[0]
    return num, ver


def get_slot(conn, slot):
    rows = q(conn, """
        SELECT slot_name, plugin, slot_type, database, active, active_pid,
               restart_lsn::text, confirmed_flush_lsn::text, pg_current_wal_lsn()::text,
               temporary
        FROM pg_replication_slots WHERE slot_name = %s""", (slot,))
    if not rows:
        fail("slot %r does not exist on this server" % slot)
    r = rows[0]
    keys = ["slot_name", "plugin", "slot_type", "database", "active", "active_pid",
            "restart_lsn", "confirmed_flush_lsn", "current_lsn", "temporary"]
    s = dict(zip(keys, r))
    if s["slot_type"] != "logical":
        fail("slot %r is a physical slot; only logical slots can be decoded" % slot)
    (db,) = q(conn, "SELECT current_database()")[0]
    if s["database"] != db:
        fail("slot %r belongs to database %r; connect to that database (you are in %r)"
             % (slot, s["database"], db))
    return s


def publications_from_walsender(conn, active_pid):
    """A native subscriber's walsender runs START_REPLICATION ... publication_names '"p1","p2"'."""
    if not active_pid:
        return []
    rows = q(conn, "SELECT query FROM pg_stat_activity WHERE pid = %s", (active_pid,))
    if not rows or not rows[0][0]:
        return []
    # native subscriber: publication_names '"p1","p2"'; pg_recvlogical: "publication_names" 'p1'
    m = re.search(r"\"?publication_names\"?\s+'((?:[^']|'')*)'", rows[0][0])
    if not m:
        return []
    raw = m.group(1).replace("''", "'")
    names = []
    for part in re.findall(r'"((?:[^"]|"")*)"|([^,]+)', raw):
        name = part[0].replace('""', '"') if part[0] else part[1].strip()
        if name:
            names.append(name)
    return names


def free_slot_count(conn):
    (n,) = q(conn, """SELECT current_setting('max_replication_slots')::int - count(*)
                      FROM pg_replication_slots""")[0]
    return n


PAUSE_HELP = """
The slot is in use by PID {pid} and this server (PostgreSQL {ver}) has no
pg_copy_logical_replication_slot (added in 12), so it can only be peeked while its consumer
is disconnected. Peeking does not consume anything, and application writes are not affected
while the consumer is paused; replication only lags (and the slot keeps retaining WAL).

  Native subscription (run on the SUBSCRIBER):
      ALTER SUBSCRIPTION <sub> DISABLE;      -- then re-run this tool
      ALTER SUBSCRIPTION <sub> ENABLE;       -- when done
  pglogical (run on the SUBSCRIBER):
      SELECT pglogical.alter_subscription_disable('<sub>', true);
      SELECT pglogical.alter_subscription_enable('<sub>', true);
  Debezium / AWS DMS / other CDC: stop the connector or task, then start it again.

Check on the publisher that the slot is free:  SELECT active FROM pg_replication_slots
WHERE slot_name = '{slot}';  -- must be false
"""


# --------------------------------------------------------------------------- pgoutput decoder
class Reader:
    def __init__(self, b):
        self.b, self.p = b, 0

    def u8(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def i16(self):
        v = struct.unpack_from("!h", self.b, self.p)[0]
        self.p += 2
        return v

    def i32(self):
        v = struct.unpack_from("!i", self.b, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from("!I", self.b, self.p)[0]
        self.p += 4
        return v

    def i64(self):
        v = struct.unpack_from("!q", self.b, self.p)[0]
        self.p += 8
        return v

    def cstr(self):
        end = self.b.index(0, self.p)
        s = self.b[self.p:end].decode("utf-8", "replace")
        self.p = end + 1
        return s

    def raw(self, n):
        v = self.b[self.p:self.p + n]
        self.p += n
        return v


def pg_ts(us):
    return (PG_EPOCH + dt.timedelta(microseconds=us)).astimezone()


def read_tuple(r, rel):
    """TupleData -> {col: value | None}, list of unchanged-TOAST column names."""
    n = r.i16()
    vals, toast = {}, []
    for i in range(n):
        col = rel["cols"][i]["name"] if i < len(rel["cols"]) else "col%d" % (i + 1)
        kind = chr(r.u8())
        if kind == "n":
            vals[col] = None
        elif kind == "u":
            toast.append(col)
        elif kind in ("t", "b"):
            ln = r.i32()
            data = r.raw(ln)
            vals[col] = data.decode("utf-8", "replace") if kind == "t" else "\\x" + data.hex()
        else:
            raise ValueError("unknown tuple column kind %r" % kind)
    return vals, toast


def key_of(rel, vals):
    keys = [c["name"] for c in rel["cols"] if c["key"]]
    return {k: vals.get(k) for k in keys if k in vals}


class PgoutputDecoder:
    """Protocol 1 messages, plus the streaming messages of protocol 2 and logical messages.
    Two-phase messages are not supported (see README)."""

    def __init__(self):
        self.rels = {}
        self.txn = None            # current non-streamed transaction
        self.streams = {}          # xid -> list of changes (streamed, not yet committed)
        self.in_stream = None      # xid of the open stream block
        self.out = []              # finished changes

    def _change(self, xid, lsn, **kw):
        c = dict(lsn=lsn, xid=xid, commit_lsn=None, end_lsn=None, commit_time=None,
                 status="committed", origin=None)
        c.update(kw)
        if self.in_stream is not None:
            # streamed changes carry the (sub)transaction xid; group them by top-level xid
            c["subxid"], c["xid"] = xid, self.in_stream
            self.streams.setdefault(self.in_stream, []).append(c)
        elif self.txn is not None:
            c["origin"] = self.txn.get("origin")
            self.txn["changes"].append(c)
        else:                       # non-transactional message outside a transaction
            self.out.append(c)

    def _finish(self, changes, commit_lsn, end_lsn, ts, status="committed"):
        for c in changes:
            c.update(commit_lsn=commit_lsn, end_lsn=end_lsn, commit_time=ts, status=status)
        self.out.extend(changes)

    def feed(self, lsn, data):
        r = Reader(bytes(data))
        t = chr(r.u8())
        streamed = self.in_stream is not None and t in "RYIUDTM"
        sxid = r.u32() if streamed else None
        xid = sxid if streamed else (self.txn["xid"] if self.txn else None)
        if t == "B":
            final_lsn, ts, txid = r.i64(), r.i64(), r.u32()
            self.txn = dict(xid=txid, changes=[], origin=None)
        elif t == "C":
            r.u8()
            commit_lsn, end_lsn, ts = r.i64(), r.i64(), r.i64()
            if self.txn:
                self._finish(self.txn["changes"], lsn_str(commit_lsn), lsn_str(end_lsn), pg_ts(ts))
            self.txn = None
        elif t == "O":
            r.i64()
            name = r.cstr()
            if self.txn:
                self.txn["origin"] = name
        elif t == "R":
            relid, nsp, name, ident, natts = r.u32(), r.cstr(), r.cstr(), chr(r.u8()), r.i16()
            cols = []
            for _ in range(natts):
                flags, cname, typoid, typmod = r.u8(), r.cstr(), r.u32(), r.i32()
                cols.append(dict(name=cname, key=bool(flags & 1), typoid=typoid))
            self.rels[relid] = dict(schema=nsp, table=name, ident=ident, cols=cols)
        elif t == "Y":
            r.u32(); r.cstr(); r.cstr()
        elif t == "I":
            rel = self.rels[r.u32()]
            r.u8()  # 'N'
            new, toast = read_tuple(r, rel)
            self._change(xid, lsn, schema=rel["schema"], table=rel["table"], op="INSERT",
                         key=key_of(rel, new), old=None, new=new, toast=toast, ident=rel["ident"])
        elif t == "U":
            rel = self.rels[r.u32()]
            kind = chr(r.u8())
            old = None
            if kind in "KO":
                old, _ = read_tuple(r, rel)
                if kind == "K":   # old KEY tuple: non-key columns are sent as NULL, drop them
                    old = key_of(rel, old)
                r.u8()  # 'N'
            new, toast = read_tuple(r, rel)
            self._change(xid, lsn, schema=rel["schema"], table=rel["table"], op="UPDATE",
                         key=key_of(rel, old if old is not None else new), old=old, new=new,
                         toast=toast, ident=rel["ident"])
        elif t == "D":
            rel = self.rels[r.u32()]
            kind = chr(r.u8())  # 'K' or 'O'
            old, _ = read_tuple(r, rel)
            if kind == "K":
                old = key_of(rel, old)
            self._change(xid, lsn, schema=rel["schema"], table=rel["table"], op="DELETE",
                         key=key_of(rel, old), old=old, new=None, toast=[], ident=rel["ident"])
        elif t == "T":
            n, opts = r.i32(), r.u8()
            for _ in range(n):
                rel = self.rels.get(r.u32(), dict(schema="?", table="?"))
                flags = (["CASCADE"] if opts & 1 else []) + (["RESTART IDENTITY"] if opts & 2 else [])
                self._change(xid, lsn, schema=rel["schema"], table=rel["table"], op="TRUNCATE",
                             key={}, old=None, new=None, toast=[], ident=None,
                             detail=" ".join(flags))
        elif t == "M":
            flags = r.u8()
            r.i64()
            prefix = r.cstr()
            content = r.raw(r.i32()).decode("utf-8", "replace")
            self._change(xid, lsn, schema=None, table=None, op="MESSAGE", key={}, old=None,
                         new={"prefix": prefix, "content": content}, toast=[], ident=None,
                         detail="transactional" if flags & 1 else "non-transactional")
        elif t == "S":
            self.in_stream = r.u32()
            r.u8()
        elif t == "E":
            self.in_stream = None
        elif t == "c":
            sx = r.u32()
            r.u8()
            commit_lsn, end_lsn, ts = r.i64(), r.i64(), r.i64()
            self._finish(self.streams.pop(sx, []), lsn_str(commit_lsn), lsn_str(end_lsn), pg_ts(ts))
        elif t == "A":
            sx, sub = r.u32(), r.u32()
            if sx == sub:
                self.streams.pop(sx, None)   # whole streamed transaction rolled back
            else:                            # a rolled-back subtransaction (savepoint)
                self.streams[sx] = [c for c in self.streams.get(sx, []) if c.get("subxid") != sub]
        # anything else (two-phase 'b','P','K','r','p') is not supported and ignored

    def finish(self):
        """Changes of transactions not committed within the scanned range."""
        for sx, changes in self.streams.items():
            for c in changes:
                c["status"] = "open"
            self.out.extend(changes)
        if self.txn:
            for c in self.txn["changes"]:
                c["status"] = "open"
            self.out.extend(self.txn["changes"])
        return self.out


# --------------------------------------------------------------------------- test_decoding parser
TD_CHANGE = re.compile(r'^table (?P<rel>.+?): (?P<op>INSERT|UPDATE|DELETE|TRUNCATE): ?(?P<rest>.*)$', re.S)
TD_BEGIN = re.compile(r"^BEGIN (\d+)")
TD_COMMIT = re.compile(r"^COMMIT (\d+)(?: \(at (.+)\))?")


def split_qualified(s):
    parts, cur, i, inq = [], "", 0, False
    while i < len(s):
        ch = s[i]
        if inq:
            if ch == '"' and i + 1 < len(s) and s[i + 1] == '"':
                cur += '"'; i += 1
            elif ch == '"':
                inq = False
            else:
                cur += ch
        elif ch == '"':
            inq = True
        elif ch == ".":
            parts.append(cur); cur = ""
        else:
            cur += ch
        i += 1
    parts.append(cur)
    return (parts[0], parts[1]) if len(parts) == 2 else (None, parts[-1])


# One token per column, plus the "old-key:" / "new-tuple:" markers of UPDATE lines. The same
# expression is used by slot_peek.sql (PostgreSQL ARE syntax), so both tools parse identically.
TD_TOKEN = re.compile(r"""(old-key:|new-tuple:)|(?:"((?:[^"]|"")+)"|([^\["\s]+))\[((?:[^\]]|\](?!:))*)\]:"""
                      r"""(null|unchanged-toast-datum|B?'(?:[^']|'')*'|\S*)""")


def parse_td_tuples(s):
    """test_decoding column list -> (old, new, toast). old is set only after 'old-key:'."""
    target, old, new, toast = "new", None, {}, []
    for m in TD_TOKEN.finditer(s):
        marker, qname, name, _typ, val = m.groups()
        if marker:
            target = "old" if marker == "old-key:" else "new"
            if target == "old":
                old = {}
            continue
        name = qname.replace('""', '"') if qname is not None else name
        if val == "unchanged-toast-datum":
            toast.append(name)
            continue
        if val == "null":
            v = None
        elif val.startswith("B'"):
            v = val[2:-1]
        elif val.startswith("'"):
            v = val[1:-1].replace("''", "'")
        else:
            v = val
        (old if target == "old" else new)[name] = v
    return old, new, toast


class TextDecoder:
    def __init__(self, keycols):
        self.keycols = keycols       # (schema, table) -> [pk columns] from the current catalog
        self.txn = None
        self.out = []

    def feed(self, lsn, xid, line):
        m = TD_BEGIN.match(line)
        if m:
            self.txn = dict(xid=int(m.group(1)), changes=[])
            return
        m = TD_COMMIT.match(line)
        if m:
            ts = m.group(2)
            for c in (self.txn or {}).get("changes", []):
                # test_decoding reports the commit record's END position on the COMMIT row
                c.update(commit_lsn=None, end_lsn=lsn, commit_time=ts, status="committed")
            self.out.extend((self.txn or {}).get("changes", []))
            self.txn = None
            return
        m = TD_CHANGE.match(line)
        if m:
            schema, table = split_qualified(m.group("rel"))
            op, rest = m.group("op"), m.group("rest")
            old = new = None
            toast, detail = [], None
            if op == "TRUNCATE":
                detail = "" if rest == "(no-flags)" else rest
            elif rest == "(no-tuple-data)":
                detail = "no replica identity data"
            elif op == "DELETE":
                _, old, _ = parse_td_tuples(rest)
            else:
                old, new, toast = parse_td_tuples(rest)
            src = old if old is not None else (new or {})
            pk = self.keycols.get((schema, table)) or []
            key = {k: src.get(k) for k in pk if k in src} if pk else (dict(old) if old else {})
            c = dict(lsn=lsn, xid=xid, commit_lsn=None, end_lsn=None, commit_time=None,
                     status="committed", origin=None, schema=schema, table=table, op=op,
                     key=key, old=old, new=new, toast=toast, ident=None, detail=detail)
            if self.txn is not None:
                self.txn["changes"].append(c)
            else:
                self.out.append(c)
            return
        if line.startswith("message:"):
            m = re.match(r"message: transactional: (\d) prefix: (.*?), sz: \d+ content:(.*)$", line, re.S)
            new = {"prefix": m.group(2), "content": m.group(3)} if m else {"content": line}
            c = dict(lsn=lsn, xid=xid, commit_lsn=None, end_lsn=None, commit_time=None,
                     status="committed", origin=None, schema=None, table=None, op="MESSAGE",
                     key={}, old=None, new=new, toast=[], ident=None,
                     detail=("transactional" if m.group(1) == "1" else "non-transactional") if m else None)
            (self.txn["changes"] if self.txn is not None else self.out).append(c)

    def finish(self):
        if self.txn:
            for c in self.txn["changes"]:
                c["status"] = "open"
            self.out.extend(self.txn["changes"])
        return self.out


# --------------------------------------------------------------------------- peek
def peek(conn, args):
    num, ver = server_info(conn)
    s = get_slot(conn, args.slot)
    info = dict(server=ver, slot=s["slot_name"], plugin=s["plugin"], active=s["active"],
                confirmed=s["confirmed_flush_lsn"], current=s["current_lsn"])
    pubs = args.publication or []
    decoder = args.decoder
    if decoder == "auto":
        if s["plugin"] == "pgoutput":
            if not pubs:
                pubs = publications_from_walsender(conn, s["active_pid"])
            decoder = "pgoutput" if pubs else "text"
            if not pubs:
                why = ("the subscriber's command is not visible to this role (needs pg_read_all_stats)"
                       if s["active"] else "slot not in use by a native subscriber")
                info["note"] = ("publication names unknown (%s); showing ALL tables. "
                                "Pass --publication to filter." % why)
        else:
            decoder = "text"
    if decoder == "pgoutput" and not pubs:
        fail("--decoder pgoutput needs --publication (could not detect it from an active walsender)")
    if decoder == "text" and num < 120000 and s["plugin"] != "test_decoding":
        fail("the text decoder needs PostgreSQL 12+ for this %s slot (it copies the slot as "
             "test_decoding); use --decoder pgoutput --publication ..." % s["plugin"])
    if decoder == "pgoutput" and num < 120000 and s["plugin"] != "pgoutput":
        fail("on PostgreSQL %s a %s slot can only be read with its own plugin" % (ver, s["plugin"]))

    q(conn, "SELECT set_config('statement_timeout', %s, false)", (str(args.timeout * 1000),))
    q(conn, "SELECT set_config('application_name', 'slot_peek', false)")
    if num >= 140000 and decoder == "pgoutput":
        # small chunks: a huge transaction is streamed in pieces instead of decoded whole
        q(conn, "SELECT set_config('logical_decoding_work_mem', %s, false)", (args.decoding_mem,))

    if num >= 120000:
        if free_slot_count(conn) < 1:
            fail("no free replication slot for the temporary copy: raise max_replication_slots "
                 "or drop an unused slot")
        target = "slot_peek_%d" % q(conn, "SELECT pg_backend_pid()")[0][0]
        plugin = "pgoutput" if decoder == "pgoutput" else "test_decoding"
        q(conn, "SELECT pg_copy_logical_replication_slot(%s, %s, true, %s)",
          (s["slot_name"], target, plugin))
        info["method"] = "temporary copy %s (%s); original slot untouched" % (target, plugin)
    else:
        if s["active"]:
            sys.exit(PAUSE_HELP.format(pid=s["active_pid"], ver=ver, slot=s["slot_name"]))
        target = s["slot_name"]
        info["method"] = "direct peek of the inactive slot (PostgreSQL %s)" % ver

    try:
        if decoder == "pgoutput":
            opts = ["proto_version", "1", "publication_names",
                    ",".join(quote_ident(p) for p in pubs)]
            if num >= 140000:
                opts = ["proto_version", "2", "publication_names", opts[3],
                        "streaming", "on", "messages", "true"]
            ph = ", ".join(["%s"] * len(opts))
            rows = q(conn, "SELECT lsn::text, data FROM pg_logical_slot_peek_binary_changes"
                           "(%%s, NULL, %%s, %s)" % ph, [target, args.limit] + opts)
            dec = PgoutputDecoder()
            for lsn, data in rows:
                dec.feed(lsn, data)
            changes = dec.finish()
            info["decoder"] = "pgoutput (publications: %s)" % ", ".join(pubs)
        else:
            window_end = lsn_int(s["confirmed_flush_lsn"]) + args.wal_window * 1024 * 1024
            upto = lsn_str(min(window_end, lsn_int(s["current_lsn"])))
            rows = q(conn, "SELECT lsn::text, xid::text::bigint, data FROM pg_logical_slot_peek_changes"
                           "(%s, %s::pg_lsn, %s, 'include-xids', '1', 'include-timestamp', '1',"
                           " 'skip-empty-xacts', '1')", (target, upto, args.limit))
            keycols = {}
            for nsp, rel, cols in q(conn, """
                    SELECT n.nspname, c.relname, array_agg(a.attname::text ORDER BY k.ord)
                    FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
                    JOIN pg_namespace n ON n.oid = c.relnamespace
                    CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum, ord)
                    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
                    WHERE i.indisprimary GROUP BY 1, 2"""):
                keycols[(nsp, rel)] = list(cols)
            dec = TextDecoder(keycols)
            for lsn, xid, data in rows:
                dec.feed(lsn, xid, data)
            changes = dec.finish()
            info["decoder"] = "text via test_decoding (all tables of the database)"
            info["window"] = "WAL scanned up to %s (--wal-window %d MB)" % (upto, args.wal_window)
    finally:
        if num >= 120000:
            q(conn, "SELECT pg_drop_replication_slot(%s)", (target,))
    info["rows_read"] = len(rows)
    if args.table:
        wanted = set(args.table)
        changes = [c for c in changes if c["op"] == "MESSAGE"
                   or "%s.%s" % (c["schema"], c["table"]) in wanted or c["table"] in wanted]
    if args.since_lsn:
        cut = lsn_int(args.since_lsn)
        info["since"] = args.since_lsn
        for c in changes:   # the subscriber's origin records the commit END lsn of each applied txn
            c["applied"] = c["end_lsn"] is not None and lsn_int(c["end_lsn"]) <= cut
    return info, changes


# --------------------------------------------------------------------------- output
def fmt_val(v):
    return "NULL" if v is None else repr(v) if not isinstance(v, str) else v


def change_text(c):
    if c["op"] == "INSERT":
        return ", ".join("%s=%s" % (k, fmt_val(v)) for k, v in c["new"].items())
    if c["op"] == "UPDATE":
        parts = []
        for k, v in c["new"].items():
            ov = (c["old"] or {}).get(k, v)
            if c["old"] and k in c["old"] and ov != v:
                parts.append("%s: %s -> %s" % (k, fmt_val(ov), fmt_val(v)))
            elif not c["old"] and k not in c["key"]:
                parts.append("%s=%s" % (k, fmt_val(v)))
        if c["toast"]:
            parts.append("(unchanged TOAST: %s)" % ", ".join(c["toast"]))
        return ", ".join(parts)
    if c["op"] == "DELETE":
        return c.get("detail") or ""
    if c["op"] == "MESSAGE":
        return "%s %s" % (c.get("detail") or "", json.dumps(c["new"]))
    return c.get("detail") or ""


def relname(c):
    return "%s.%s" % (c["schema"], c["table"]) if c["table"] else "-"


def print_summary(info, changes, out):
    p = lambda *a: print(*a, file=out)
    backlog = lsn_int(info["current"]) - lsn_int(info["confirmed"])
    p("Slot            : %s  (plugin %s, %s)" % (info["slot"], info["plugin"],
                                                  "in use" if info["active"] else "not in use"))
    p("Server          : PostgreSQL %s" % info["server"])
    p("Method          : %s" % info["method"])
    p("Decoder         : %s" % info["decoder"])
    p("Pending WAL     : %s  (confirmed_flush_lsn %s -> current %s)"
      % (pretty_bytes(backlog), info["confirmed"], info["current"]))
    if info.get("window"):
        p("Scanned         : %s" % info["window"])
    if info.get("note"):
        p("Note            : %s" % info["note"])
    p("Rows decoded    : %d (limit %s; applied at transaction or stream-chunk boundaries)"
      % (info["rows_read"], info["limit"]))
    if info["rows_read"] >= info["limit"]:
        p("Stopped early   : limit reached - more changes may follow; raise --limit to see them")
    data = [c for c in changes if c["op"] != "MESSAGE"]
    xids = {c["xid"] for c in data}
    committed = {c["xid"] for c in data if c["status"] == "committed"}
    p("Transactions    : %d committed, %d open (no commit seen in the scanned range)"
      % (len(committed), len(xids - committed)))
    times = sorted(str(c["commit_time"]) for c in data if c["commit_time"])
    if times:
        p("Commit time     : %s  ..  %s" % (times[0], times[-1]))
    lsns = [c["end_lsn"] for c in data if c["end_lsn"]]
    if lsns:
        p("Commit end LSN  : %s  ..  %s" % (min(lsns, key=lsn_int), max(lsns, key=lsn_int)))
    if "since" in info:
        un = [c for c in data if not c.get("applied")]
        p("Not yet applied : %d changes in %d transactions after %s"
          % (len(un), len({c["xid"] for c in un}), info["since"]))
    per = {}
    for c in data:
        k = relname(c)
        per.setdefault(k, {"INSERT": 0, "UPDATE": 0, "DELETE": 0, "TRUNCATE": 0})
        per[k][c["op"]] += 1
    if per:
        p("")
        w = max(12, max(len(k) for k in per))
        p("%-*s %8s %8s %8s %8s" % (w, "table", "insert", "update", "delete", "truncate"))
        for k in sorted(per):
            v = per[k]
            p("%-*s %8d %8d %8d %8d" % (w, k, v["INSERT"], v["UPDATE"], v["DELETE"], v["TRUNCATE"]))
    if xids:
        sizes = {}
        for c in data:
            sizes[c["xid"]] = sizes.get(c["xid"], 0) + 1
        big = max(sizes, key=sizes.get)
        p("")
        p("Largest transaction: xid %s with %d changes" % (big, sizes[big]))
    msgs = [c for c in changes if c["op"] == "MESSAGE"]
    if msgs:
        p("Logical messages: %d" % len(msgs))


def print_table(changes, out, width=70, per_txn=20):
    hdr = ["end_lsn", "commit_time", "xid", "status", "table", "op", "key", "change"]
    rows = []
    shown, hidden = {}, {}
    for c in changes:
        n = shown.get(c["xid"], 0)
        if per_txn and n >= per_txn:
            hidden[c["xid"]] = hidden.get(c["xid"], 0) + 1
            continue
        shown[c["xid"]] = n + 1
        ct = str(c["commit_time"])[:23] if c["commit_time"] else ""
        st = c["status"] + (" (applied)" if c.get("applied") else "")
        ch = change_text(c)
        rows.append([c["end_lsn"] or "", ct, str(c["xid"]), st, relname(c), c["op"],
                     json.dumps(c["key"], ensure_ascii=False) if c["key"] else "",
                     ch if len(ch) <= width else ch[:width - 3] + "..."])
    ws = [max(len(h), *(len(r[i]) for r in rows)) if rows else len(h) for i, h in enumerate(hdr)]
    print("  ".join(h.ljust(ws[i]) for i, h in enumerate(hdr)), file=out)
    print("  ".join("-" * w for w in ws), file=out)
    for r in rows:
        print("  ".join(v.ljust(ws[i]) for i, v in enumerate(r)), file=out)
    for xid, n in hidden.items():
        print("... %d more changes of xid %s not shown (--per-txn %d; use --format csv/jsonl/sql for all)"
              % (n, xid, per_txn), file=out)


def as_record(c):
    return dict(commit_lsn=c["commit_lsn"], end_lsn=c["end_lsn"],
                commit_time=str(c["commit_time"]) if c["commit_time"] else None,
                xid=c["xid"], status=c["status"], applied=c.get("applied"), origin=c["origin"],
                schema=c["schema"], table=c["table"], op=c["op"], key=c["key"], old=c["old"],
                new=c["new"], unchanged_toast=c["toast"], lsn=c["lsn"])


def sql_for(c):
    if c["op"] == "MESSAGE":
        return "-- logical message: %s" % json.dumps(c["new"], ensure_ascii=False)
    t = "%s.%s" % (quote_ident(c["schema"]), quote_ident(c["table"]))
    lit = lambda v: "NULL" if v is None else quote_literal(v)

    def where(d):
        return " AND ".join("%s %s" % (quote_ident(k), "IS NULL" if v is None else "= " + lit(v))
                            for k, v in d.items())
    if c["op"] == "INSERT":
        cols = list(c["new"])
        return "INSERT INTO %s (%s) VALUES (%s);" % (
            t, ", ".join(map(quote_ident, cols)), ", ".join(lit(c["new"][k]) for k in cols))
    if c["op"] == "UPDATE":
        if not c["key"]:
            return "-- UPDATE on %s skipped: no key (replica identity) data" % t
        sets = ", ".join("%s = %s" % (quote_ident(k), lit(v)) for k, v in c["new"].items())
        return "UPDATE %s SET %s WHERE %s;" % (t, sets, where(c["key"]))
    if c["op"] == "DELETE":
        if not c["key"]:
            return "-- DELETE on %s skipped: no key (replica identity) data" % t
        return "DELETE FROM %s WHERE %s;" % (t, where(c["key"]))
    if c["op"] == "TRUNCATE":
        return "TRUNCATE %s%s;" % (t, (" " + c["detail"]) if c.get("detail") else "")
    return "-- logical message: %s" % json.dumps(c["new"])


def print_sql(info, changes, out):
    p = lambda *a: print(*a, file=out)
    p("-- Generated by slot_peek.py %s from slot %s, %s" % (VERSION, info["slot"], dt.datetime.now().isoformat(timespec="seconds")))
    p("-- Review before running. Unchanged TOAST columns are left out of UPDATE SET lists.")
    if "since" in info:
        p("-- Only transactions with end_lsn after %s (not yet applied by the subscriber)." % info["since"])
    cur = None
    for c in changes:
        if c.get("applied") or c["op"] == "MESSAGE" and not c["xid"]:
            continue
        if c["status"] != "committed":
            continue
        if c["xid"] != cur:
            if cur is not None:
                p("COMMIT;")
            cur = c["xid"]
            p("\n-- xid %s committed %s, end_lsn %s" % (c["xid"], c["commit_time"], c["end_lsn"]))
            p("BEGIN;")
        p(sql_for(c))
    if cur is not None:
        p("COMMIT;")
    skipped = sum(1 for c in changes if c["status"] != "committed")
    if skipped:
        p("-- %d changes of transactions not committed in the scanned range were not included." % skipped)


def overview(conn, out):
    num, ver = server_info(conn)
    rows = q(conn, """
        SELECT s.slot_name, s.plugin, s.database, s.active, s.active_pid,
               coalesce(a.application_name, ''), coalesce(host(a.client_addr), ''),
               pg_wal_lsn_diff(pg_current_wal_lsn(), s.confirmed_flush_lsn)::bigint,
               pg_wal_lsn_diff(pg_current_wal_lsn(), s.restart_lsn)::bigint
        FROM pg_replication_slots s LEFT JOIN pg_stat_activity a ON a.pid = s.active_pid
        WHERE s.slot_type = 'logical' ORDER BY 1""")
    (db,) = q(conn, "SELECT current_database()")[0]
    free = free_slot_count(conn)
    print("PostgreSQL %s, database %s, free replication slots: %d" % (ver, db, free), file=out)
    if not rows:
        print("No logical replication slots.", file=out)
        return
    hdr = ["slot", "plugin", "database", "in use by", "pending WAL", "retained WAL", "how to inspect"]
    table = []
    for name, plugin, sdb, active, pid, app, addr, pend, ret in rows:
        user = ("pid %s %s %s" % (pid, app, addr)).strip() if active else "-"
        if sdb != db:
            how = "connect to database %s" % sdb
        elif num >= 120000:
            how = "peek --slot %s" % name + ("" if plugin == "pgoutput" else "  (text decoder)")
        elif active:
            how = "pause the consumer first (README), then peek"
        elif plugin in ("pgoutput", "test_decoding"):
            how = "peek --slot %s" % name
        else:
            how = "not supported on PostgreSQL < 12 (%s)" % plugin
        table.append([name, plugin, sdb, user, pretty_bytes(pend), pretty_bytes(ret), how])
    ws = [max(len(h), *(len(r[i]) for r in table)) for i, h in enumerate(hdr)]
    print("  ".join(h.ljust(ws[i]) for i, h in enumerate(hdr)), file=out)
    print("  ".join("-" * w for w in ws), file=out)
    for r in table:
        print("  ".join(v.ljust(ws[i]) for i, v in enumerate(r)), file=out)
    if free < 1 and num >= 120000:
        print("\nWARNING: no free slot; peek needs one for its temporary copy.", file=out)


def position(conn, out):
    rows = q(conn, """
        SELECT s.subname, s.subenabled, s.subslotname, o.remote_lsn::text,
               array_to_string(s.subpublications, ',')
        FROM pg_subscription s
        LEFT JOIN pg_replication_origin_status o ON o.external_id = 'pg_' || s.oid
        WHERE s.subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
        ORDER BY 1""")
    if not rows:
        print("No subscriptions in this database.", file=out)
        return
    print("%-20s %-8s %-20s %-16s %s" % ("subscription", "enabled", "slot", "applied up to", "publications"), file=out)
    for name, en, slot, lsn, pubs in rows:
        print("%-20s %-8s %-20s %-16s %s" % (name, en, slot, lsn or "-", pubs), file=out)
    print("\nUse 'applied up to' as --since-lsn on the publisher to list changes not yet applied.", file=out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["overview", "peek", "position"])
    ap.add_argument("--dsn", default="", help="libpq connection string (default: PG* environment)")
    ap.add_argument("--slot", help="slot to inspect (peek)")
    ap.add_argument("--publication", action="append", help="publication name (repeatable); auto-detected when the slot is in use")
    ap.add_argument("--decoder", choices=["auto", "pgoutput", "text"], default="auto")
    ap.add_argument("--limit", type=int, default=1000, help="stop after about this many decoded rows (default 1000)")
    ap.add_argument("--wal-window", type=int, default=256, help="text decoder: MB of WAL to scan after confirmed_flush_lsn (default 256)")
    ap.add_argument("--decoding-mem", default="1MB", help="pgoutput on 14+: logical_decoding_work_mem for this session (default 1MB)")
    ap.add_argument("--timeout", type=int, default=300, help="statement timeout in seconds (default 300)")
    ap.add_argument("--since-lsn", help="subscriber's applied LSN (from 'position'); marks or skips changes already applied")
    ap.add_argument("--table", action="append", help="only this table (schema.table or table; repeatable)")
    ap.add_argument("--format", choices=["summary", "table", "csv", "jsonl", "sql"], default="table",
                    help="table = summary + one line per change (default)")
    ap.add_argument("--per-txn", type=int, default=20, help="table format: changes shown per transaction (default 20, 0 = all)")
    ap.add_argument("--output", help="write to this file instead of stdout")
    args = ap.parse_args()
    out = open(args.output, "w", encoding="utf-8") if args.output else sys.stdout
    conn = connect(args.dsn)
    try:
        if args.command == "overview":
            overview(conn, out)
        elif args.command == "position":
            position(conn, out)
        else:
            if not args.slot:
                fail("peek needs --slot")
            info, changes = peek(conn, args)
            info["limit"] = args.limit
            if args.format in ("summary", "table"):
                print_summary(info, changes, out)
                if args.format == "table" and changes:
                    print("", file=out)
                    print_table(changes, out, per_txn=args.per_txn)
            elif args.format == "jsonl":
                for c in changes:
                    print(json.dumps(as_record(c), ensure_ascii=False, default=str), file=out)
            elif args.format == "csv":
                w = csv.writer(out)
                recs = [as_record(c) for c in changes]
                cols = list(as_record(changes[0]).keys()) if changes else ["commit_lsn"]
                w.writerow(cols)
                for r in recs:
                    w.writerow([json.dumps(r[k], ensure_ascii=False) if isinstance(r[k], (dict, list)) else r[k] for k in cols])
            else:
                print_sql(info, changes, out)
    finally:
        conn.close()
        if args.output:
            out.close()


if __name__ == "__main__":
    main()
