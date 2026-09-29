#!/usr/bin/env bash
set -euo pipefail

: "${LAB_DIR:?LAB_DIR must point to an initialized lab}"
WATCHER="$LAB_DIR/monitor/watcher.py"
[[ -f "$WATCHER" ]] || { echo "missing watcher: $WATCHER" >&2; exit 1; }

input="$(mktemp)"
output="$(mktemp)"
trap 'rm -f "$input" "$output"' EXIT

cat >"$input" <<'LOG'
2026-09-29 14:00:00 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] LOG: connection authorized: user=dashboard_vendor database=vendorlab
2026-09-29 14:00:01 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] LOG: statement: SELECT EXTRACT(YEAR FROM created_at), count(*) FROM public.transactions GROUP BY 1;
2026-09-29 14:00:02 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] LOG: execute <unnamed>: WITH x AS (SELECT * FROM public.customers) SELECT count(*) FROM x;
2026-09-29 14:00:03 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] LOG: statement: SELECT * FROM information_schema.columns;
2026-09-29 14:00:04 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] LOG: statement: UPDATE public.customers SET country='US';
2026-09-29 14:00:05 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] ERROR: permission denied for schema internal_test
2026-09-29 14:00:05 UTC [pid=1 user=dashboard_vendor db=vendorlab app=test client=203.0.113.10:50000] STATEMENT: SELECT * FROM internal_test.research_notes;
2026-09-29 14:00:06 UTC [pid=2 user=lab_admin db=vendorlab app=[unknown] client=198.51.100.2:51000] FATAL: password authentication failed for user "lab_admin"
2026-09-29 14:00:07 UTC [pid=3 user=[unknown] db=[unknown] app=[unknown] client=198.51.100.3:51001] FATAL: no pg_hba.conf entry for host "198.51.100.3", user "postgres", database "vendorlab", no encryption
2026-09-29 14:00:08 UTC [pid=4 user=dashboard_vendor db=vendorlab app=test client=198.51.100.4:51002] LOG: connection authorized: user=dashboard_vendor database=vendorlab
2026-09-29 14:00:09 UTC [pid=4 user=dashboard_vendor db=vendorlab app=test client=198.51.100.4:51002] LOG: statement: SET default_transaction_read_only = off;
LOG

VENDOR_USER=dashboard_vendor \
ALLOWED_IPS=203.0.113.10 \
REPLAY_MODE=1 \
ALERT_LOG='' \
python3 "$WATCHER" <"$input" >"$output"

for expected in \
  'Reason: WRITE ATTEMPT' \
  'Reason: PERMISSION DENIED' \
  'Reason: CANARY ACCESS' \
  'Reason: AUTHENTICATION FAILURE' \
  'Reason: PG_HBA REJECTION' \
  'Reason: UNEXPECTED SOURCE IP: 198.51.100.4' \
  'Reason: READ-WRITE OVERRIDE'
do
  grep -Fq "$expected" "$output" || {
    echo "missing expected watcher result: $expected" >&2
    cat "$output" >&2
    exit 1
  }
done

if grep -Fq 'UNAPPROVED' "$output"; then
  echo 'normal BI metadata/query syntax produced an unexpected scope alert' >&2
  cat "$output" >&2
  exit 1
fi

echo 'watcher smoke test: PASS'
