#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/db_vendor_test_lab.sh"
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
LAB_DIR="${LAB_DIR:-$RUNNER_TEMP/db-access-lab-e2e}"
export LAB_DIR
watch_pid=""

cleanup() {
  if [[ -n "$watch_pid" ]]; then
    kill "$watch_pid" >/dev/null 2>&1 || true
    wait "$watch_pid" 2>/dev/null || true
  fi
  if [[ -f "$LAB_DIR/.env" ]]; then
    "$SCRIPT" destroy --yes >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

"$SCRIPT" init
"$SCRIPT" start

set -a
# shellcheck disable=SC1091
source "$LAB_DIR/.env"
set +a

conn="host=127.0.0.1 port=$DB_PORT dbname=$DB_NAME user=$VENDOR_USER password=$VENDOR_PASSWORD"
psql_image="${POSTGRES_IMAGE:-postgres:16}"


# TLS connection and approved SELECT must work.
docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=require" -v ON_ERROR_STOP=1 \
  -Atqc 'SELECT count(*) FROM public.customers' | grep -Eq '^[0-9]+$'

# Plaintext TCP must fail.
if docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=disable" -Atqc 'SELECT 1' >/dev/null 2>&1; then
  echo 'plaintext database connection unexpectedly succeeded' >&2
  exit 1
fi

# Start live watcher after initialization logs are complete.
"$SCRIPT" watch >"$RUNNER_TEMP/watcher.out" 2>&1 &
watch_pid=$!
sleep 2

# Write must fail.
if docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=require" -v ON_ERROR_STOP=1 \
  -c "UPDATE public.customers SET country='US' WHERE customer_id=1" >/dev/null 2>&1; then
  echo 'vendor UPDATE unexpectedly succeeded' >&2
  exit 1
fi

# Canary must fail.
if docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=require" -v ON_ERROR_STOP=1 \
  -c 'SELECT * FROM internal_test.research_notes' >/dev/null 2>&1; then
  echo 'vendor canary access unexpectedly succeeded' >&2
  exit 1
fi

# TEMP creation must fail because PUBLIC database privileges were revoked.
if docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=require" -v ON_ERROR_STOP=1 \
  -c 'CREATE TEMP TABLE should_fail(id int)' >/dev/null 2>&1; then
  echo 'vendor TEMP privilege unexpectedly succeeded' >&2
  exit 1
fi

# A read-write override may be accepted as a setting, but must be observable and
# must not grant write privileges.
docker run --rm --network host "$psql_image" \
  psql "$conn sslmode=require" -v ON_ERROR_STOP=1 \
  -c 'SET default_transaction_read_only = off' >/dev/null

sleep 3
kill "$watch_pid" >/dev/null 2>&1 || true
wait "$watch_pid" 2>/dev/null || true
watch_pid=""

for expected in \
  'Reason: WRITE ATTEMPT' \
  'Reason: PERMISSION DENIED' \
  'Reason: CANARY ACCESS' \
  'Reason: DDL ATTEMPT' \
  'Reason: READ-WRITE OVERRIDE'
do
  grep -Fq "$expected" "$RUNNER_TEMP/watcher.out" || {
    echo "missing live watcher result: $expected" >&2
    cat "$RUNNER_TEMP/watcher.out" >&2
    exit 1
  }
done

"$SCRIPT" evidence >/dev/null

latest="$(find "$LAB_DIR/evidence" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
[[ -n "$latest" && -f "$latest/SHA256SUMS.txt" ]] || {
  echo 'evidence snapshot or hash manifest missing' >&2
  exit 1
}

"$SCRIPT" destroy --yes
trap - EXIT

[[ ! -e "$LAB_DIR/.env" ]] || { echo '.env remained after destroy' >&2; exit 1; }
[[ ! -e "$LAB_DIR/tls/server.key" ]] || { echo 'TLS private key remained after destroy' >&2; exit 1; }

echo 'docker e2e: PASS'
