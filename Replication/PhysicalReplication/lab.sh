#!/usr/bin/env bash
# Throwaway streaming-replication lab for the physical-replication notes.
#
#   source lab.sh
#   plab_up              # primary :5433 + standby :5435 (streaming, hot standby)
#   prim -c "select 1"   # psql to the primary
#   stby -c "select 1"   # psql to the standby
#   plab_add_standby2    # second standby :5436 (cascading from the first, see topic 08)
#   plab_down            # stop everything and delete $LAB
#
# Everything lives under $LAB (default /tmp/pr-lab). Tested with PostgreSQL 18.6.
# Extra postgresql.conf lines for the primary can be passed to plab_up as arguments.

PGBIN=${PGBIN:-$(pg_config --bindir)}
LAB=${LAB:-/tmp/pr-lab}
P_PORT=${P_PORT:-5433}
S_PORT=${S_PORT:-5435}
S2_PORT=${S2_PORT:-5436}

prim()  { "$PGBIN/psql" -X -h 127.0.0.1 -p "$P_PORT"  -d postgres "$@"; }
stby()  { "$PGBIN/psql" -X -h 127.0.0.1 -p "$S_PORT"  -d postgres "$@"; }
stby2() { "$PGBIN/psql" -X -h 127.0.0.1 -p "$S2_PORT" -d postgres "$@"; }

_conf() {  # _conf <datadir> <port> [extra lines...]
  local d=$1 port=$2; shift 2
  {
    echo "port = $port"
    echo "listen_addresses = '127.0.0.1'"
    echo "unix_socket_directories = '$LAB'"
    echo "log_line_prefix = '%m [%p] %a '"
    printf '%s\n' "$@"
  } >> "$d/postgresql.conf"
}

plab_up() {
  plab_down 2>/dev/null
  mkdir -p "$LAB"
  "$PGBIN/initdb" -D "$LAB/primary" -A trust >/dev/null
  _conf "$LAB/primary" "$P_PORT" "$@"
  # allow the replication user (database 'replication' = physical connections)
  sed -i '1i host replication repl 127.0.0.1/32 trust' "$LAB/primary/pg_hba.conf"
  "$PGBIN/pg_ctl" -D "$LAB/primary" -l "$LAB/primary.log" -w start >/dev/null
  prim -q -c "CREATE ROLE repl LOGIN REPLICATION"
  # NOTE: pg_basebackup -R writes dbname=$PGDATABASE into primary_conninfo (PG17+);
  # export a real database name so slot sync / logical tooling does not break.
  PGDATABASE=postgres "$PGBIN/pg_basebackup" -h 127.0.0.1 -p "$P_PORT" -U repl \
      -D "$LAB/standby" -R -X stream >/dev/null 2>&1
  _conf "$LAB/standby" "$S_PORT"
  "$PGBIN/pg_ctl" -D "$LAB/standby" -l "$LAB/standby.log" -w start >/dev/null
  echo "primary :$P_PORT  standby :$S_PORT  ($("$PGBIN/postgres" --version))"
}

plab_add_standby2() {  # cascading: standby2 streams from standby 1
  sed -i '1i host replication repl 127.0.0.1/32 trust' "$LAB/standby/pg_hba.conf" 2>/dev/null
  stby -q -c "select pg_reload_conf()" >/dev/null
  PGDATABASE=postgres "$PGBIN/pg_basebackup" -h 127.0.0.1 -p "$S_PORT" -U repl \
      -D "$LAB/standby2" -R -X stream >/dev/null 2>&1
  _conf "$LAB/standby2" "$S2_PORT"
  "$PGBIN/pg_ctl" -D "$LAB/standby2" -l "$LAB/standby2.log" -w start >/dev/null
}

plab_down() {
  for n in standby2 standby primary; do
    [ -d "$LAB/$n" ] && "$PGBIN/pg_ctl" -D "$LAB/$n" -m immediate stop >/dev/null 2>&1
  done
  rm -rf "$LAB"
}
