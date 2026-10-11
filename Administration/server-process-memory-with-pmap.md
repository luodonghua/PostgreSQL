# Inspecting Backend Process Memory with pmap

Every client connection to PostgreSQL is served by a dedicated backend process
forked from the postmaster. The Linux `pmap` command prints the memory map of a
running process — each mapped region with its address, size, permissions, and
backing object. Running `pmap` against a backend PID is a quick way to see how
PostgreSQL's shared memory, shared libraries, and process-private allocations
are laid out, and to understand why a backend's reported memory footprint is
mostly *shared* rather than *private*.

This note walks through locating a specific backend and reading its `pmap`
output on an Amazon Linux host running PostgreSQL.

## Finding the backend PID

From inside `psql`, `pg_backend_pid()` returns the OS process ID serving the
current session:

```text
postgres=# select pg_backend_pid();
 pg_backend_pid 
----------------
           2278
(1 row)
```

The matching row in `pg_stat_activity` confirms the client, its address, and
that the session is currently `active`:

```text
postgres=# \x 
Expanded display is on.
postgres=# select * from pg_stat_activity where pid = pg_backend_pid();
-[ RECORD 1 ]----+-------------------------------------------------------------
datid            | 14231
datname          | postgres
pid              | 2278
leader_pid       | 
usesysid         | 16384
usename          | donghua
application_name | psql
client_addr      | 116.14.204.216
client_hostname  | 
client_port      | 51331
backend_start    | 2021-10-31 13:01:34.664489+00
xact_start       | 2021-10-31 13:05:35.6382+00
query_start      | 2021-10-31 13:05:35.6382+00
state_change     | 2021-10-31 13:05:35.638202+00
wait_event_type  | 
wait_event       | 
state            | active
backend_xid      | 
backend_xmin     | 489
query            | select * from pg_stat_activity where pid = pg_backend_pid();
backend_type     | client backend
```

On the host, `ps` shows the same PID as an idle backend owned by `postgres`:

```bash
ps -ef | grep 2278 | grep -v grep
```

```text
postgres  2278  2107  0 13:01 ?        00:00:00 postgres: donghua postgres 116.14.204.216(51331) idle
```

## Reading the memory map

Run `pmap` with the backend PID:

```bash
pmap 2278
```

The output lists every mapped region. Each line is `address  size  permissions
backing`:

```text
2278:   postgres: donghua postgres 116.14.204.216(51331) idle
0000000000400000   7196K r-x-- postgres
0000000000d06000      4K r---- postgres
0000000000d07000     60K rw--- postgres
0000000000d16000    204K rw---   [ anon ]
00000000022b2000    360K rw---   [ anon ]
000000000230c000   1156K rw---   [ anon ]
00007fa0b8e6c000     44K r-x-- libnss_files-2.26.so
00007fa0b8e77000   2044K ----- libnss_files-2.26.so
00007fa0b9076000      4K r---- libnss_files-2.26.so
00007fa0b9077000      4K rw--- libnss_files-2.26.so
00007fa0b9078000     24K rw---   [ anon ]
00007fa0b907e000 145624K rw-s- zero (deleted)
00007fa0c1eb4000 110400K r---- locale-archive
00007fa0c8a84000     60K r-x-- libbz2.so.1.0.6
00007fa0c8a93000   2044K ----- libbz2.so.1.0.6
00007fa0c8c92000      4K r---- libbz2.so.1.0.6
00007fa0c8c93000      4K rw--- libbz2.so.1.0.6
00007fa0c8c94000     92K r-x-- libelf-0.176.so
00007fa0c8cab000   2044K ----- libelf-0.176.so
00007fa0c8eaa000      4K r---- libelf-0.176.so
00007fa0c8eab000      4K rw--- libelf-0.176.so
00007fa0c8eac000    396K r-x-- libpcre.so.1.2.0
00007fa0c8f0f000   2044K ----- libpcre.so.1.2.0
00007fa0c910e000      4K r---- libpcre.so.1.2.0
00007fa0c910f000      4K rw--- libpcre.so.1.2.0

... (dozens of shared libraries follow with the same four-mapping pattern: r-x-- text, ----- guard gap, r---- read-only data, rw--- writable data) ...

00007fa0ca469000  20296K r-x-- libicudata.so.50.2
00007fa0cb83b000   2044K ----- libicudata.so.50.2
00007fa0cba3a000      4K r---- libicudata.so.50.2
00007fa0cba3b000      4K rw--- libicudata.so.50.2

... (more libraries: libstdc++, libnss3, libssl3, libkrb5, libcrypto, libssl, libxml2, libc, libpthread, etc.) ...

00007fa0ce7c2000   1668K r-x-- libc-2.26.so
00007fa0ce963000   2048K ----- libc-2.26.so
00007fa0ceb63000     16K r---- libc-2.26.so
00007fa0ceb67000      8K rw--- libc-2.26.so
00007fa0ceb69000     16K rw---   [ anon ]

... (ICU, LDAP, libm, libdl, librt, GSSAPI, OpenSSL, PAM, libxml2, libpthread) ...

00007fa0d0f28000    144K r-x-- ld-2.26.so
00007fa0d10c7000    392K rw---   [ anon ]
00007fa0d1129000    104K rw---   [ anon ]
00007fa0d1146000     16K rw-s- PostgreSQL.2032231456
00007fa0d114a000      4K rw-s-   [ shmid=0x38000 ]
00007fa0d114b000      4K r---- ld-2.26.so
00007fa0d114c000      4K rw--- ld-2.26.so
00007fa0d114d000      4K rw---   [ anon ]
00007ffd55872000    132K rw---   [ stack ]
00007ffd559aa000     12K r----   [ anon ]
00007ffd559ad000      8K r-x--   [ anon ]
ffffffffff600000      4K r-x--   [ anon ]
 total           403776K
```

## Understanding the segments

A few categories of mapping stand out:

- **The executable itself (`postgres`).** The first three lines map the
  binary: a large read-execute text segment (`7196K r-x--`), a small read-only
  segment, and a writable data segment. These are shared, copy-on-write across
  all backends.
- **Shared memory (`rw-s-`).** The permission flag `s` marks a *shared*
  mapping. The large `145624K rw-s- zero (deleted)` region near the top is
  PostgreSQL's main shared memory segment (shared buffers and related
  structures) backed by an anonymous/`mmap` shared allocation. Near the bottom,
  `16K rw-s- PostgreSQL.2032231456` and `4K rw-s- [ shmid=0x38000 ]` are
  additional shared-memory attachments. Because this memory is shared across
  every backend, it is counted once for the whole server, not per connection —
  summing per-process `pmap` totals would badly overcount real memory use.
- **`locale-archive` (`110400K r---- `).** A read-only, file-backed mapping of
  the system locale data. It is shared read-only across all processes that map
  it, so it costs essentially nothing extra per backend.
- **Shared libraries.** Each `.so` typically appears as four consecutive
  mappings: an `r-x--` text (code) segment, a `-----` inaccessible guard gap, an
  `r----` read-only data segment, and an `rw---` writable data segment. The
  code and read-only portions are shared system-wide; only the small writable
  portions are private.
- **Anonymous private memory (`rw--- [ anon ]`).** These are the process's own
  heap and working allocations — the genuinely private memory that grows with
  what this backend is actually doing.
- **Stack (`rw--- [ stack ]`).** The process stack, here 132K.
- **`vsyscall` (`ffffffffff600000 4K r-x--`).** The kernel-provided fixed
  mapping at the top of the address space.

The reported `total 403776K` (~394 MB) is the sum of *virtual* address space,
which is dominated by shared regions — the shared-memory segment and the
read-only locale archive and library code. The private, per-backend portion is
only the handful of small `[ anon ]` and stack mappings.

## Postmaster and its children

The backend's parent is the postmaster. `ps` shows PID `2107` running the
`postmaster` with its data directory:

```bash
ps -ef | grep postmaster | grep -v grep
```

```text
postgres  2107     1  0 12:56 ?        00:00:00 /usr/bin/postmaster -D /var/lib/pgsql/data
```

`pstree` shows the postmaster and all its forked children — the auxiliary
processes plus the client backend `2278` inspected above:

```bash
pstree -p -h 2107
```

```text
postmaster(2107)─┬─postmaster(2111)
                 ├─postmaster(2113)
                 ├─postmaster(2114)
                 ├─postmaster(2115)
                 ├─postmaster(2116)
                 ├─postmaster(2117)
                 ├─postmaster(2118)
                 └─postmaster(2278)
```

Each child shares the same `postgres`/`postmaster` executable image and
attaches to the same shared-memory segment — which is exactly why their `pmap`
totals overlap so heavily.

## Takeaways

- Find a backend's OS PID with `pg_backend_pid()` and correlate it to a
  connection via `pg_stat_activity` and `ps`.
- `pmap <pid>` prints the full virtual memory map; the per-line permissions
  tell you what each region is — `r-x--` code, `r----` read-only data, `rw---`
  writable private data, and `rw-s-` shared memory.
- PostgreSQL's large shared-memory segment (here `~145 MB`, shown as `rw-s-
  zero (deleted)`) and the read-only `locale-archive` and shared-library code
  are shared across all backends, so they are counted once per server, not once
  per connection.
- The `pmap` grand total is virtual address space and is dominated by shared
  mappings; a backend's genuinely private memory is just the small anonymous
  (`[ anon ]`) heap and stack regions.
- Because every backend is forked from the postmaster and attaches to the same
  shared memory, naively summing per-process memory numbers massively
  overstates the server's real memory consumption.
