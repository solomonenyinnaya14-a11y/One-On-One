#!/usr/bin/env bash
# Applies the bootstrap, every migration (in order) and every test file to a
# scratch database, then drops it. Never touches a real Supabase project.
#
# Usage: supabase/tests/run.sh            (uses the standard PG* environment)
#   PGHOST=/var/tmp/pgtest PGPORT=54329 PGUSER=postgres supabase/tests/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
db="oneonone_test_$$"

admin() { psql -X -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
scratch() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

cleanup() { admin -c "drop database if exists \"$db\" with (force)" >/dev/null 2>&1 || true; }
trap cleanup EXIT

admin -c "create database \"$db\""

echo "== bootstrap"
scratch -f "$here/00_bootstrap.sql"

for f in "$root"/migrations/*.sql; do
  echo "== migration $(basename "$f")"
  scratch -f "$f"
done

shopt -s nullglob
for f in "$here"/[1-9]*.sql; do
  echo "== test $(basename "$f")"
  scratch -f "$f"
done

echo "== all database checks passed"
