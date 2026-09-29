#!/usr/bin/env bash
set -euo pipefail

# db_vendor_test_lab.sh
#
# Disposable PostgreSQL lab for validating a third-party BI/dashboard vendor.
#
# Goals:
#   - Keep the vendor completely away from production.
#   - Use synthetic data only.
#   - Give the vendor a dedicated SELECT-only account.
#   - Log connections, queries, failures, and source IPs.
#   - Alert on activity outside the agreed dashboard scope.
#   - Preserve evidence and destroy the lab when finished.
#
# This script is intentionally conservative. It does NOT attack, probe, or
# access the vendor's systems. Everything happens inside infrastructure you own.
#
# Requirements:
#   - Linux/macOS with Bash
#   - Docker with "docker compose"
#   - Python 3
#   - openssl
#
# Typical workflow:
#
#   chmod +x db_vendor_test_lab.sh
#   ./db_vendor_test_lab.sh init
#   ./db_vendor_test_lab.sh start
#   ./db_vendor_test_lab.sh creds
#   ./db_vendor_test_lab.sh watch
#
# After the vendor finishes:
#
#   ./db_vendor_test_lab.sh evidence
#   ./db_vendor_test_lab.sh stop
#   ./db_vendor_test_lab.sh destroy
#
# IMPORTANT:
#   By default PostgreSQL binds to 127.0.0.1 only.
#   If the vendor must connect over the internet, put the lab on a disposable
#   VPS, firewall the port to the vendor's outbound IPs, and then change
#   BIND_ADDR in .env to 0.0.0.0.
#
#   Do NOT expose this from a workstation, corporate network, VPN-connected
#   machine, or any host containing useful credentials.

LAB_DIR="${LAB_DIR:-$PWD/db-vendor-test-lab}"
ENV_FILE="$LAB_DIR/.env"
COMPOSE_FILE="$LAB_DIR/docker-compose.yml"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '\n==> %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_base_tools() {
  require_cmd docker
  require_cmd python3
  require_cmd openssl
  docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required: docker compose'
}

random_secret() {
  openssl rand -hex 24
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Lab is not initialized. Run: $0 init"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

escape_sql_literal() {
  # Generated secrets are hex-only, but keep this helper for safety.
  printf "%s" "$1" | sed "s/'/''/g"
}

write_env() {
  local admin_password vendor_password
  admin_password="$(random_secret)"
  vendor_password="$(random_secret)"

  cat >"$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=db_vendor_test_lab
POSTGRES_IMAGE=postgres:16
BIND_ADDR=127.0.0.1
DB_PORT=55432

DB_NAME=vendorlab
ADMIN_USER=lab_admin
ADMIN_PASSWORD=$admin_password

VENDOR_USER=dashboard_vendor
VENDOR_PASSWORD=$vendor_password

# Optional. If set, watcher.py will POST alerts here.
DISCORD_WEBHOOK_URL=
EOF

  chmod 600 "$ENV_FILE"
}

write_compose() {
  cat >"$COMPOSE_FILE" <<'EOF'
services:
  postgres:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${ADMIN_USER}
      POSTGRES_PASSWORD: ${ADMIN_PASSWORD}
    ports:
      - "${BIND_ADDR}:${DB_PORT}:5432"
    volumes:
      - db_vendor_lab_data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d:ro
    command:
      - postgres
      - -c
      - log_connections=on
      - -c
      - log_disconnections=on
      - -c
      - log_statement=all
      - -c
      - log_duration=on
      - -c
      - log_min_error_statement=error
      - -c
      - "log_line_prefix=%m [pid=%p user=%u db=%d app=%a client=%r] "
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${ADMIN_USER} -d ${DB_NAME}"]
      interval: 3s
      timeout: 3s
      retries: 20

volumes:
  db_vendor_lab_data:
EOF
}

write_schema() {
  cat >"$LAB_DIR/init/01-schema.sql" <<'EOF'
CREATE TABLE customers (
    customer_id     BIGSERIAL PRIMARY KEY,
    customer_name   TEXT NOT NULL,
    email           TEXT NOT NULL,
    country         TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL
);

CREATE TABLE subscriptions (
    subscription_id BIGSERIAL PRIMARY KEY,
    customer_id     BIGINT NOT NULL REFERENCES customers(customer_id),
    plan_name       TEXT NOT NULL,
    monthly_price   NUMERIC(10,2) NOT NULL,
    status          TEXT NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL
);

CREATE TABLE transactions (
    transaction_id  BIGSERIAL PRIMARY KEY,
    customer_id     BIGINT NOT NULL REFERENCES customers(customer_id),
    amount           NUMERIC(10,2) NOT NULL,
    currency         TEXT NOT NULL DEFAULT 'USD',
    status           TEXT NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL
);

CREATE TABLE api_usage (
    usage_id         BIGSERIAL PRIMARY KEY,
    customer_id      BIGINT NOT NULL REFERENCES customers(customer_id),
    endpoint         TEXT NOT NULL,
    status_code      INTEGER NOT NULL,
    response_ms      INTEGER NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL
);

CREATE TABLE invoices (
    invoice_id       BIGSERIAL PRIMARY KEY,
    customer_id      BIGINT NOT NULL REFERENCES customers(customer_id),
    amount            NUMERIC(10,2) NOT NULL,
    invoice_status    TEXT NOT NULL,
    issued_at         TIMESTAMPTZ NOT NULL
);

-- Canary area.
-- This is deliberately unrelated to the dashboard request and is NOT granted
-- to the vendor. A permission-denied attempt against it is worth reviewing.
CREATE SCHEMA internal_test;

CREATE TABLE internal_test.research_notes (
    note_id BIGSERIAL PRIMARY KEY,
    note_text TEXT NOT NULL
);

INSERT INTO internal_test.research_notes(note_text)
VALUES
('Synthetic canary object. This contains no real secret or production data.');
EOF
}

write_fake_data() {
  cat >"$LAB_DIR/init/02-fake-data.sql" <<'EOF'
INSERT INTO customers(customer_name, email, country, created_at)
SELECT
    'Customer ' || gs,
    'customer' || gs || '@example.invalid',
    (ARRAY['US','CA','GB','DE','FR','AU'])[1 + (random() * 5)::int],
    NOW() - ((random() * 365)::int || ' days')::interval
FROM generate_series(1, 500) AS gs;

INSERT INTO subscriptions(customer_id, plan_name, monthly_price, status, started_at)
SELECT
    customer_id,
    (ARRAY['Starter','Growth','Pro','Enterprise'])[1 + (random() * 3)::int],
    ROUND((20 + random() * 480)::numeric, 2),
    (ARRAY['active','active','active','paused','cancelled'])[1 + (random() * 4)::int],
    NOW() - ((random() * 300)::int || ' days')::interval
FROM customers;

INSERT INTO transactions(customer_id, amount, currency, status, created_at)
SELECT
    1 + (random() * 499)::int,
    ROUND((5 + random() * 2500)::numeric, 2),
    'USD',
    (ARRAY['paid','paid','paid','failed','refunded'])[1 + (random() * 4)::int],
    NOW() - ((random() * 180)::int || ' days')::interval
FROM generate_series(1, 6000);

INSERT INTO api_usage(customer_id, endpoint, status_code, response_ms, created_at)
SELECT
    1 + (random() * 499)::int,
    (ARRAY['/v1/search','/v1/export','/v1/jobs','/v1/results'])[1 + (random() * 3)::int],
    (ARRAY[200,200,200,201,400,404,429,500])[1 + (random() * 7)::int],
    20 + (random() * 1800)::int,
    NOW() - ((random() * 90)::int || ' days')::interval
FROM generate_series(1, 12000);

INSERT INTO invoices(customer_id, amount, invoice_status, issued_at)
SELECT
    1 + (random() * 499)::int,
    ROUND((20 + random() * 5000)::numeric, 2),
    (ARRAY['paid','paid','open','past_due'])[1 + (random() * 3)::int],
    NOW() - ((random() * 365)::int || ' days')::interval
FROM generate_series(1, 2500);
EOF
}

write_permissions() {
  load_env
  local vendor_pw
  vendor_pw="$(escape_sql_literal "$VENDOR_PASSWORD")"

  cat >"$LAB_DIR/init/03-permissions.sql" <<EOF
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE ROLE "$VENDOR_USER"
    LOGIN
    PASSWORD '$vendor_pw'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    CONNECTION LIMIT 5;

GRANT CONNECT ON DATABASE "$DB_NAME" TO "$VENDOR_USER";
GRANT USAGE ON SCHEMA public TO "$VENDOR_USER";

GRANT SELECT ON TABLE
    public.customers,
    public.subscriptions,
    public.transactions,
    public.api_usage,
    public.invoices
TO "$VENDOR_USER";

REVOKE ALL ON SCHEMA internal_test FROM "$VENDOR_USER";
REVOKE ALL ON ALL TABLES IN SCHEMA internal_test FROM "$VENDOR_USER";

ALTER ROLE "$VENDOR_USER" SET default_transaction_read_only = on;
ALTER ROLE "$VENDOR_USER" SET statement_timeout = '30s';
ALTER ROLE "$VENDOR_USER" SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE "$VENDOR_USER" SET lock_timeout = '5s';
ALTER ROLE "$VENDOR_USER" SET search_path = public;
EOF
}

write_watcher() {
  cat >"$LAB_DIR/monitor/watcher.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

VENDOR_USER = os.environ.get("VENDOR_USER", "dashboard_vendor")
WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()

APPROVED_RELATIONS = {
    "customers",
    "subscriptions",
    "transactions",
    "api_usage",
    "invoices",
}

NORMAL_METADATA_PREFIXES = (
    "information_schema.",
    "pg_catalog.",
)

HIGH_SIGNAL_PATTERNS = [
    ("WRITE ATTEMPT", re.compile(r"\b(insert|update|delete|merge|truncate)\b", re.I)),
    ("DDL ATTEMPT", re.compile(r"\b(create|alter|drop)\b", re.I)),
    ("PRIVILEGE ATTEMPT", re.compile(r"\b(grant|revoke|set\s+role|reset\s+role)\b", re.I)),
    ("COPY ATTEMPT", re.compile(r"\bcopy\b", re.I)),
    ("SENSITIVE CATALOG ACCESS", re.compile(
        r"\b(pg_authid|pg_shadow|pg_user_mapping|pg_hba_file_rules)\b", re.I
    )),
    ("SERVER FILE FUNCTION", re.compile(
        r"\b(pg_read_file|pg_read_binary_file|pg_ls_dir|pg_stat_file|lo_import|lo_export)\b",
        re.I,
    )),
    ("CANARY ACCESS", re.compile(r"\binternal_test\b", re.I)),
]

RELATION_RE = re.compile(
    r'\b(?:from|join|update|into|table)\s+("?[\w]+"?(?:\."?[\w]+"?)?)',
    re.I,
)

def post_discord(message: str) -> None:
    if not WEBHOOK:
        return
    body = json.dumps({"content": message[:1900]}).encode()
    req = urllib.request.Request(
        WEBHOOK,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=5).read()
    except Exception as exc:
        print(f"[watcher] Discord alert failed: {exc}", file=sys.stderr)

def normalize_relation(raw: str) -> str:
    return raw.replace('"', '').lower()

def classify(statement: str):
    hits = []

    for label, pattern in HIGH_SIGNAL_PATTERNS:
        if pattern.search(statement):
            hits.append(label)

    for raw in RELATION_RE.findall(statement):
        rel = normalize_relation(raw)

        if rel.startswith(NORMAL_METADATA_PREFIXES):
            continue

        if "." in rel:
            schema, table = rel.split(".", 1)
            if schema == "public" and table in APPROVED_RELATIONS:
                continue
            if schema == "internal_test":
                if "CANARY ACCESS" not in hits:
                    hits.append("CANARY ACCESS")
                continue
            hits.append(f"UNAPPROVED RELATION: {rel}")
            continue

        if rel not in APPROVED_RELATIONS:
            # Avoid flagging common SQL functions or aliases unless they appear
            # as a relation target after FROM/JOIN/etc.
            hits.append(f"UNAPPROVED RELATION: {rel}")

    return list(dict.fromkeys(hits))

def emit_alert(reason: str, line: str):
    now = datetime.now(timezone.utc).isoformat()
    msg = (
        "[DB TEST ALERT]\n"
        f"Time: {now}\n"
        f"User: {VENDOR_USER}\n"
        f"Reason: {reason}\n"
        f"Log: {line.strip()}"
    )
    print("\n" + msg + "\n", flush=True)
    post_discord(msg)

def main():
    print(f"[watcher] Watching PostgreSQL logs for user={VENDOR_USER}", flush=True)
    if WEBHOOK:
        print("[watcher] Discord webhook alerts enabled", flush=True)
    else:
        print("[watcher] Discord webhook not configured; terminal alerts only", flush=True)

    for line in sys.stdin:
        sys.stdout.write(line)
        sys.stdout.flush()

        # Only analyze lines tied to the vendor role.
        if f"user={VENDOR_USER} " not in line and f"user={VENDOR_USER}]" not in line:
            continue

        lower = line.lower()

        if "permission denied" in lower:
            emit_alert("PERMISSION DENIED", line)
            continue

        if "password authentication failed" in lower:
            emit_alert("AUTHENTICATION FAILURE", line)
            continue

        marker = "statement:"
        idx = lower.find(marker)
        if idx == -1:
            continue

        statement = line[idx + len(marker):].strip()

        for reason in classify(statement):
            emit_alert(reason, line)

if __name__ == "__main__":
    main()
PY

  chmod +x "$LAB_DIR/monitor/watcher.py"
}

write_reference() {
  cat >"$LAB_DIR/TEST_PLAN.txt" <<'EOF'
DATABASE VENDOR TEST PLAN

Purpose

Validate whether a BI/dashboard vendor behaves like the product they claim to
operate without exposing any real data, real credentials, or production system.

1. Environment

Use a disposable VM or VPS.

Do not run this from:
- A production server
- A corporate workstation
- A machine connected to a company VPN
- A host containing useful SSH keys, cloud credentials, tokens, or secrets

2. Data

Use synthetic data only.

The lab contains:
- customers
- subscriptions
- transactions
- api_usage
- invoices

Nothing in the database should identify a real person or business.

3. Vendor access

Give the vendor only the credentials printed by:

    ./db_vendor_test_lab.sh creds

The vendor account is read-only.

It does not have:
- INSERT
- UPDATE
- DELETE
- CREATE
- ALTER
- DROP
- Admin
- Superuser
- Ownership permissions

4. Network

Ask the vendor for the outbound IP addresses used by their connector.

On an internet-facing VPS:
- Restrict the database port to those IP addresses with the VPS/cloud firewall
- Require TLS before using this for anything beyond a short controlled test
- Do not expose other services from the host

The script binds PostgreSQL to 127.0.0.1 by default.

Only change BIND_ADDR to 0.0.0.0 after the firewall rule is ready.

5. Agreed dashboard request

Give the vendor a specific assignment.

Example:

Build a dashboard showing:
- Revenue over time
- Transactions per day
- Top customers
- Subscription distribution
- API usage
- Error rate

This defines what normal activity should look like.

6. Monitoring

Run:

    ./db_vendor_test_lab.sh watch

The watcher prints all PostgreSQL activity and raises higher-signal alerts for:
- Write attempts
- DDL attempts
- Privilege changes
- COPY attempts
- Sensitive PostgreSQL catalog access
- Server-side file functions
- Permission-denied events
- Access to the canary schema
- References to relations outside the approved dataset

Normal BI tools often inspect information_schema and pg_catalog.
Metadata discovery alone is not treated as proof of malicious behavior.

7. Canary

The database contains:

    internal_test.research_notes

The vendor has no access to this schema.

The dashboard assignment gives them no reason to use it.

An access attempt should be documented and reviewed, but one event alone should
not be treated as proof of malicious intent.

8. Evidence

Before shutting down the lab, run:

    ./db_vendor_test_lab.sh evidence

Preserve:
- Database logs
- Source IP addresses
- Timestamps
- Queries
- Discord messages
- Emails
- Screenshots
- Company/domain information
- Names provided by the vendor

9. Stop conditions

Stop the test if the vendor:
- Demands production credentials
- Requires admin or write access without a clear technical need
- Tries to access data outside the agreed scope
- Attempts privilege changes
- Tries to use server-side file access
- Refuses basic company/security questions while requesting sensitive access

10. Cleanup

After evidence is saved:

    ./db_vendor_test_lab.sh destroy

Destroy the VPS when the test is complete.

Do not reuse:
- Database passwords
- Test credentials
- Hostnames
- Certificates
- API tokens

11. Boundary

Do not attack the vendor.

Do not:
- Scan systems you do not own
- Exploit anything
- Credential-stuff accounts
- Attempt unauthorized access
- Disrupt their service

The purpose is to observe how they use access that you intentionally gave them
inside infrastructure you control.
EOF
}

cmd_init() {
  require_base_tools

  if [[ -e "$ENV_FILE" ]]; then
    die "Lab already exists at $LAB_DIR. Destroy it first or set LAB_DIR to a new path."
  fi

  note "Creating lab at $LAB_DIR"
  mkdir -p "$LAB_DIR/init" "$LAB_DIR/monitor" "$LAB_DIR/evidence"

  write_env
  write_compose
  write_schema
  write_fake_data
  write_permissions
  write_watcher
  write_reference

  cat >"$LAB_DIR/.gitignore" <<'EOF'
.env
evidence/*
!evidence/.gitkeep
EOF
  touch "$LAB_DIR/evidence/.gitkeep"

  note "Lab created"
  printf '%s\n' \
    "Next:" \
    "  cd \"$LAB_DIR\"" \
    "  $0 start" \
    "  $0 creds" \
    "  $0 watch"
}

cmd_start() {
  require_base_tools
  load_env

  if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    printf '\nWARNING: PostgreSQL is configured for internet exposure.\n'
    printf 'Confirm your VPS/cloud firewall allows only the vendor outbound IPs.\n\n'
  fi

  note "Starting disposable PostgreSQL lab"
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" up -d
  )

  note "Waiting for PostgreSQL health check"
  local i
  for i in $(seq 1 30); do
    if (
      cd "$LAB_DIR"
      docker compose --env-file "$ENV_FILE" exec -T postgres \
        pg_isready -U "$ADMIN_USER" -d "$DB_NAME" >/dev/null 2>&1
    ); then
      note "Database is ready"
      cmd_creds
      return
    fi
    sleep 2
  done

  die "PostgreSQL did not become ready. Run: $0 status"
}

cmd_creds() {
  load_env

  cat <<EOF

VENDOR TEST CREDENTIALS

Host:     <LAB VPS HOSTNAME OR IP>
Port:     $DB_PORT
Database: $DB_NAME
Username: $VENDOR_USER
Password: $VENDOR_PASSWORD

Permissions:
SELECT only on:
  public.customers
  public.subscriptions
  public.transactions
  public.api_usage
  public.invoices

Do not send the admin credentials to the vendor.

EOF
}

cmd_watch() {
  require_base_tools
  load_env

  note "Starting live query watcher"
  printf 'Press Ctrl-C to stop watching. The database will keep running.\n\n'

  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" logs -f --no-color postgres
  ) | (
    export VENDOR_USER DISCORD_WEBHOOK_URL
    python3 "$LAB_DIR/monitor/watcher.py"
  )
}

cmd_status() {
  require_base_tools
  load_env

  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" ps
  )
}

cmd_evidence() {
  require_base_tools
  load_env

  local stamp out
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="$LAB_DIR/evidence/$stamp"
  mkdir -p "$out"

  note "Saving evidence snapshot to $out"

  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" logs --no-color postgres
  ) >"$out/postgres.log" 2>&1 || true

  cp "$LAB_DIR/TEST_PLAN.txt" "$out/"
  cp "$LAB_DIR/docker-compose.yml" "$out/"
  cp "$LAB_DIR/init/01-schema.sql" "$out/"
  cp "$LAB_DIR/init/02-fake-data.sql" "$out/"
  cp "$LAB_DIR/init/03-permissions.sql" "$out/"

  # Save configuration without passwords/webhook values.
  grep -Ev '^(ADMIN_PASSWORD|VENDOR_PASSWORD|DISCORD_WEBHOOK_URL)=' "$ENV_FILE" \
    >"$out/environment-redacted.txt"

  (
    cd "$out"
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 ./* >SHA256SUMS.txt
    elif command -v sha256sum >/dev/null 2>&1; then
      sha256sum ./* >SHA256SUMS.txt
    fi
  )

  note "Evidence snapshot complete"
  printf '%s\n' "$out"
}

cmd_stop() {
  require_base_tools
  load_env

  note "Stopping lab"
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" stop
  )
}

cmd_destroy() {
  require_base_tools
  load_env

  cat <<EOF

This permanently removes the PostgreSQL container and database volume.

Evidence under:
  $LAB_DIR/evidence

is left in place.

EOF

  note "Destroying database and Docker volume"
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" down -v --remove-orphans
  )

  note "Database destroyed"
  printf 'Delete the disposable VPS when the test is finished.\n'
}

cmd_plan() {
  if [[ -f "$LAB_DIR/TEST_PLAN.txt" ]]; then
    cat "$LAB_DIR/TEST_PLAN.txt"
    return
  fi

  cat <<'EOF'
Run:

  ./db_vendor_test_lab.sh init

The generated TEST_PLAN.txt contains the full walk-through.
EOF
}

usage() {
  cat <<EOF
Usage:
  $0 init       Create the disposable lab files
  $0 start      Start PostgreSQL and initialize fake data
  $0 creds      Print only the vendor test credentials
  $0 watch      Watch queries and alert on deviations
  $0 status     Show container status
  $0 evidence   Save logs and a redacted configuration snapshot
  $0 stop       Stop the lab without deleting data
  $0 destroy    Delete the PostgreSQL container and database volume
  $0 plan       Print the reference test plan

Default lab directory:
  $LAB_DIR

Override it with:
  LAB_DIR=/path/to/lab $0 init

Recommended sequence:
  init -> start -> creds -> watch -> evidence -> destroy
EOF
}

case "${1:-}" in
  init)     cmd_init ;;
  start)    cmd_start ;;
  creds)    cmd_creds ;;
  watch)    cmd_watch ;;
  status)   cmd_status ;;
  evidence) cmd_evidence ;;
  stop)     cmd_stop ;;
  destroy)  cmd_destroy ;;
  plan)     cmd_plan ;;
  -h|--help|help|"") usage ;;
  *) die "Unknown command: $1. Run: $0 --help" ;;
esac
