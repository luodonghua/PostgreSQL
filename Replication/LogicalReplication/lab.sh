#!/usr/bin/env bash
# Throwaway two-instance lab for the logical-replication notes.
#
#   source lab.sh
#   lab_up            # create + start publisher (5433) and subscriber (5434)
#   pub  -c "select 1"   # psql against the publisher
#   sub  -c "select 1"   # psql against the subscriber
#   lab_down          # stop both and delete the data directories
#
# Everything lives under $LAB (default /tmp/lr-lab); nothing touches an existing
# cluster. Tested with PostgreSQL 18.6 (Ubuntu pgdg package).

PGBIN=${PGBIN:-$(pg_config --bindir)}
LAB=${LAB:-/tmp/lr-lab}
PUB_PORT=${PUB_PORT:-5433}
SUB_PORT=${SUB_PORT:-5434}

pub() { "$PGBIN/psql" -X -h 127.0.0.1 -p "$PUB_PORT" -d postgres "$@"; }
sub() { "$PGBIN/psql" -X -h 127.0.0.1 -p "$SUB_PORT" -d postgres "$@"; }

_mk() {  # _mk <name> <port> [extra postgresql.conf lines...]
  local name=$1 port=$2; shift 2
  "$PGBIN/initdb" -D "$LAB/$name" -A trust >/dev/null
  {
    echo "port = $port"
    echo "listen_addresses = '127.0.0.1'"
    echo "unix_socket_directories = '$LAB'"
    echo "log_line_prefix = '%m [%p] %a '"
    printf '%s\n' "$@"
  } >> "$LAB/$name/postgresql.conf"
  "$PGBIN/pg_ctl" -D "$LAB/$name" -l "$LAB/$name.log" -w start >/dev/null
}

lab_up() {
  lab_down 2>/dev/null
  mkdir -p "$LAB"
  _mk pub "$PUB_PORT" "wal_level = logical" "$@"
  _mk sub "$SUB_PORT"
  echo "publisher :$PUB_PORT  subscriber :$SUB_PORT  ($("$PGBIN/postgres" --version))"
}

lab_down() {
  for n in pub sub; do
    [ -d "$LAB/$n" ] && "$PGBIN/pg_ctl" -D "$LAB/$n" -m immediate stop >/dev/null 2>&1
  done
  rm -rf "$LAB"
}
