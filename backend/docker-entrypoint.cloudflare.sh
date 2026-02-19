#!/usr/bin/env bash
set -euo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-pingy}"

mkdir -p "${PGDATA}"
chown -R postgres:postgres "${PGDATA}"

run_as_postgres() {
  runuser -u postgres -- "$@"
}

start_postgres() {
  run_as_postgres pg_ctl -D "${PGDATA}" -o "-p ${PGPORT} -c listen_addresses='127.0.0.1'" -w start
}

stop_postgres() {
  run_as_postgres pg_ctl -D "${PGDATA}" -m fast -w stop
}

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  run_as_postgres initdb -D "${PGDATA}"
  echo "host all all 127.0.0.1/32 trust" >> "${PGDATA}/pg_hba.conf"

  start_postgres
  run_as_postgres createdb -p "${PGPORT}" "${PGDATABASE}" || true
  psql -h 127.0.0.1 -U postgres -p "${PGPORT}" -d "${PGDATABASE}" -f /app/db/schema.sql
  stop_postgres
fi

start_postgres
psql -h 127.0.0.1 -U postgres -p "${PGPORT}" -d "${PGDATABASE}" -f /app/db/schema.sql >/dev/null

cleanup() {
  stop_postgres || true
}

trap cleanup EXIT INT TERM

exec node src/server.js
