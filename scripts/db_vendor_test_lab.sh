#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${LAB_DIR:-$SCRIPT_DIR/db-vendor-test-lab}"
ENV_FILE="$LAB_DIR/.env"
COMPOSE_FILE="$LAB_DIR/docker-compose.yml"

readonly SCRIPT_DIR LAB_DIR ENV_FILE COMPOSE_FILE


note() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_base_tools() {
  require_cmd docker
  require_cmd python3
  require_cmd openssl
  docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required.'
}

random_secret() {
  openssl rand -hex 24
}

validate_identifier() {
  local value="$1"
  local label="$2"
  [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "$label contains unsupported characters: $value"
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Lab is not initialized. Run: $0 init"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${DB_NAME:?DB_NAME is required}"
  : "${ADMIN_USER:?ADMIN_USER is required}"
  : "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required}"
  : "${VENDOR_USER:?VENDOR_USER is required}"
  : "${VENDOR_PASSWORD:?VENDOR_PASSWORD is required}"
  : "${BIND_ADDR:?BIND_ADDR is required}"
  : "${DB_PORT:?DB_PORT is required}"

  validate_identifier "$DB_NAME" DB_NAME
  validate_identifier "$ADMIN_USER" ADMIN_USER
  validate_identifier "$VENDOR_USER" VENDOR_USER
  [[ "$DB_PORT" =~ ^[0-9]+$ ]] || die "DB_PORT must be numeric."
  (( DB_PORT >= 1 && DB_PORT <= 65535 )) || die "DB_PORT must be between 1 and 65535."
}

write_env() {
  local admin_password vendor_password
  admin_password="$(random_secret)"
  vendor_password="$(random_secret)"

  umask 077
  cat >"$ENV_FILE" <<EOF_ENV
COMPOSE_PROJECT_NAME=db_vendor_test_lab
POSTGRES_IMAGE=postgres:16
BIND_ADDR=127.0.0.1
DB_PORT=55432

DB_NAME=vendorlab
ADMIN_USER=lab_admin
ADMIN_PASSWORD=$admin_password

VENDOR_USER=dashboard_vendor
VENDOR_PASSWORD=$vendor_password

# Comma-separated IPv4/IPv6 addresses or CIDRs expected from the vendor.
# This is used for monitoring. It does not configure the host firewall.
ALLOWED_IPS=

# Remote exposure is refused unless ALLOWED_IPS is populated and this is 1.
FIREWALL_CONFIRMED=0

# Emergency override. Avoid this unless you deliberately accept open exposure.
FORCE_EXPOSE=0

# Optional Discord webhook for live alerts. Leave empty for terminal-only alerts.
DISCORD_WEBHOOK_URL=
EOF_ENV
  chmod 600 "$ENV_FILE"
}

write_tls() {
  mkdir -p "$LAB_DIR/tls"
  umask 077
  openssl req \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -nodes \
    -days 7 \
    -subj '/CN=db-vendor-test-lab' \
    -keyout "$LAB_DIR/tls/server.key" \
    -out "$LAB_DIR/tls/server.crt" \
    >/dev/null 2>&1
  chmod 600 "$LAB_DIR/tls/server.key"
  chmod 644 "$LAB_DIR/tls/server.crt"
}

write_hba() {
  mkdir -p "$LAB_DIR/config"
  cat >"$LAB_DIR/config/pg_hba.conf" <<EOF_HBA
# Local socket access is confined to the container and is used by initialization.
local   all             all                                     trust

# Administrator access is only accepted over TLS from loopback inside the container.
hostssl $DB_NAME        $ADMIN_USER      127.0.0.1/32            scram-sha-256
hostssl $DB_NAME        $ADMIN_USER      ::1/128                 scram-sha-256

# Vendor access requires TLS. Network source restrictions belong in the VPS/cloud
# firewall because Docker-published ports can bypass host firewall front ends.
hostssl $DB_NAME        $VENDOR_USER     0.0.0.0/0               scram-sha-256
hostssl $DB_NAME        $VENDOR_USER     ::/0                    scram-sha-256

# Reject plaintext TCP and all other TCP roles.
hostnossl all           all              0.0.0.0/0               reject
hostnossl all           all              ::/0                    reject
host     all            all              0.0.0.0/0               reject
host     all            all              ::/0                    reject
EOF_HBA
  chmod 644 "$LAB_DIR/config/pg_hba.conf"
}

write_compose() {
  cat >"$COMPOSE_FILE" <<'EOF_COMPOSE'
services:
  tls-init:
    image: ${POSTGRES_IMAGE}
    user: root
    restart: "no"
    entrypoint:
      - /bin/sh
      - -eu
      - -c
      - |
        cp /tls-source/server.crt /tls/server.crt
        cp /tls-source/server.key /tls/server.key
        chown postgres:postgres /tls/server.crt /tls/server.key
        chmod 0644 /tls/server.crt
        chmod 0600 /tls/server.key
    command: []
    volumes:
      - ./tls:/tls-source:ro
      - db_vendor_lab_tls:/tls

  postgres:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    depends_on:
      tls-init:
        condition: service_completed_successfully
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${ADMIN_USER}
      POSTGRES_PASSWORD: ${ADMIN_PASSWORD}
      POSTGRES_INITDB_ARGS: --auth-host=scram-sha-256
      VENDOR_USER: ${VENDOR_USER}
    ports:
      - "${BIND_ADDR}:${DB_PORT}:5432"
    volumes:
      - db_vendor_lab_data:/var/lib/postgresql/data
      - db_vendor_lab_tls:/run/db-lab-tls:ro
      - ./init:/docker-entrypoint-initdb.d:ro
      - ./config/pg_hba.conf:/etc/postgresql/db-lab-pg_hba.conf:ro
    command:
      - postgres
      - -c
      - ssl=on
      - -c
      - ssl_cert_file=/run/db-lab-tls/server.crt
      - -c
      - ssl_key_file=/run/db-lab-tls/server.key
      - -c
      - hba_file=/etc/postgresql/db-lab-pg_hba.conf
      - -c
      - password_encryption=scram-sha-256
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
      test:
        - CMD-SHELL
        - >-
          psql -U "$${POSTGRES_USER}" -d "$${POSTGRES_DB}" -Atqc
          "SELECT 1 FROM pg_roles WHERE rolname = '$${VENDOR_USER}'" | grep -qx 1
      interval: 3s
      timeout: 3s
      retries: 30

volumes:
  db_vendor_lab_data:
  db_vendor_lab_tls:
EOF_COMPOSE
}

write_schema() {
  cat >"$LAB_DIR/init/01-schema.sql" <<'EOF_SQL'
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

CREATE SCHEMA internal_test;

CREATE TABLE internal_test.research_notes (
    note_id BIGSERIAL PRIMARY KEY,
    note_text TEXT NOT NULL
);

INSERT INTO internal_test.research_notes(note_text)
VALUES ('Synthetic canary object. This contains no real secret or production data.');
EOF_SQL
}

write_fake_data() {
  cat >"$LAB_DIR/init/02-fake-data.sql" <<'EOF_SQL'
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
EOF_SQL
}

write_permissions() {
  cat >"$LAB_DIR/init/03-permissions.sql" <<EOF_SQL
REVOKE ALL ON DATABASE "$DB_NAME" FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE ROLE "$VENDOR_USER"
    LOGIN
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

REVOKE ALL ON SCHEMA internal_test FROM PUBLIC;
REVOKE ALL ON SCHEMA internal_test FROM "$VENDOR_USER";
REVOKE ALL ON ALL TABLES IN SCHEMA internal_test FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA internal_test FROM "$VENDOR_USER";

ALTER ROLE "$VENDOR_USER" SET default_transaction_read_only = on;
ALTER ROLE "$VENDOR_USER" SET statement_timeout = '30s';
ALTER ROLE "$VENDOR_USER" SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE "$VENDOR_USER" SET lock_timeout = '5s';
ALTER ROLE "$VENDOR_USER" SET search_path = public;
EOF_SQL
}

write_watcher() {
  cat >"$LAB_DIR/monitor/watcher.py" <<'PY'
#!/usr/bin/env python3
import ipaddress
import json
import os
import re
import sys
import time
import urllib.request
from collections import deque
from datetime import datetime, timezone

VENDOR_USER = os.environ.get("VENDOR_USER", "dashboard_vendor")
WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
ALERT_LOG = os.environ.get("ALERT_LOG", "").strip()
REPLAY_MODE = os.environ.get("REPLAY_MODE", "0") == "1"
ALLOWED_IPS_RAW = os.environ.get("ALLOWED_IPS", "").strip()

RECORD_START = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}")
CLIENT_RE = re.compile(r"client=([^\]\s:]+|\[[^\]]+\])(?::\d+)?")
SQL_RE = re.compile(r"(?:statement|execute [^:]*):\s*(.*)", re.I | re.S)
SCHEMA_RELATION_RE = re.compile(
    r'\b(?:from|join|update|into|table)\s+"?([A-Za-z_][A-Za-z0-9_]*)"?\."?([A-Za-z_][A-Za-z0-9_]*)"?',
    re.I,
)

HIGH_SIGNAL_PATTERNS = [
    ("WRITE ATTEMPT", re.compile(r"\b(insert|update|delete|merge|truncate)\b", re.I)),
    ("DDL ATTEMPT", re.compile(r"\b(create|alter|drop)\b", re.I)),
    ("PRIVILEGE ATTEMPT", re.compile(r"\b(grant|revoke|set\s+role|reset\s+role)\b", re.I)),
    ("COPY ATTEMPT", re.compile(r"\bcopy\b", re.I)),
    ("READ-WRITE OVERRIDE", re.compile(
        r"\b(begin\s+read\s+write|set\s+(?:session\s+characteristics\s+as\s+)?transaction\s+read\s+write|default_transaction_read_only\s*(?:=|to)\s*(?:off|false|0))\b",
        re.I,
    )),
    ("SENSITIVE CATALOG ACCESS", re.compile(
        r"\b(pg_authid|pg_shadow|pg_user_mapping|pg_hba_file_rules|pg_roles|pg_user)\b", re.I
    )),
    ("SERVER FILE FUNCTION", re.compile(
        r"\b(pg_read_file|pg_read_binary_file|pg_ls_dir|pg_stat_file|lo_import|lo_export)\b",
        re.I,
    )),
    ("CANARY ACCESS", re.compile(r"\binternal_test\b", re.I)),
    ("EXTENSION ATTEMPT", re.compile(r"\bcreate\s+extension\b", re.I)),
]


def parse_allowed_networks(raw):
    networks = []
    for item in (part.strip() for part in raw.split(",")):
        if not item:
            continue
        try:
            if "/" in item:
                networks.append(ipaddress.ip_network(item, strict=False))
            else:
                addr = ipaddress.ip_address(item)
                bits = 32 if addr.version == 4 else 128
                networks.append(ipaddress.ip_network(f"{addr}/{bits}", strict=False))
        except ValueError:
            print(f"[watcher] Ignoring invalid ALLOWED_IPS entry: {item}", file=sys.stderr)
    return networks


ALLOWED_NETWORKS = parse_allowed_networks(ALLOWED_IPS_RAW)
RECENT = deque(maxlen=256)


def post_discord(message):
    if not WEBHOOK or REPLAY_MODE:
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


def append_alert(message):
    if not ALERT_LOG or REPLAY_MODE:
        return
    try:
        with open(ALERT_LOG, "a", encoding="utf-8") as handle:
            handle.write(message + "\n\n")
    except OSError as exc:
        print(f"[watcher] Failed to write alert log: {exc}", file=sys.stderr)


def emit_alert(reason, record):
    fingerprint = (reason, " ".join(record.split()))
    now_monotonic = time.monotonic()
    while RECENT and now_monotonic - RECENT[0][0] > 10:
        RECENT.popleft()
    if any(item[1] == fingerprint for item in RECENT):
        return
    RECENT.append((now_monotonic, fingerprint))

    now = datetime.now(timezone.utc).isoformat()
    msg = (
        "[DB TEST ALERT]\n"
        f"Time: {now}\n"
        f"User: {VENDOR_USER}\n"
        f"Reason: {reason}\n"
        f"Log: {record.strip()}"
    )
    print("\n" + msg + "\n", flush=True)
    append_alert(msg)
    post_discord(msg)


def extract_client(record):
    match = CLIENT_RE.search(record)
    if not match:
        return None
    value = match.group(1).strip("[]")
    try:
        return ipaddress.ip_address(value)
    except ValueError:
        return None


def client_allowed(address):
    if not ALLOWED_NETWORKS:
        return True
    return any(address in network for network in ALLOWED_NETWORKS)


def strip_literals(sql):
    sql = re.sub(r"--[^\n]*", " ", sql)
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"'(?:''|[^'])*'", "''", sql)
    sql = re.sub(r'"(?:""|[^"])*"', '""', sql)
    return sql


def classify_sql(sql):
    cleaned = strip_literals(sql)
    hits = []

    for label, pattern in HIGH_SIGNAL_PATTERNS:
        if pattern.search(cleaned):
            hits.append(label)

    for schema, table in SCHEMA_RELATION_RE.findall(cleaned):
        schema_l = schema.lower()
        if schema_l in {"public", "information_schema", "pg_catalog"}:
            continue
        if schema_l == "internal_test":
            if "CANARY ACCESS" not in hits:
                hits.append("CANARY ACCESS")
            continue
        hits.append(f"UNAPPROVED SCHEMA: {schema_l}.{table.lower()}")

    return list(dict.fromkeys(hits))


def analyze_record(record):
    lower = record.lower()

    if "password authentication failed" in lower:
        emit_alert("AUTHENTICATION FAILURE", record)
        return

    if "no pg_hba.conf entry" in lower or "pg_hba.conf rejects connection" in lower:
        emit_alert("PG_HBA REJECTION", record)
        return

    if f"user={VENDOR_USER}" in record and "connection authorized" in lower:
        address = extract_client(record)
        if address is not None and not client_allowed(address):
            emit_alert(f"UNEXPECTED SOURCE IP: {address}", record)

    if f"user={VENDOR_USER}" not in record:
        return

    if "permission denied" in lower:
        emit_alert("PERMISSION DENIED", record)

    match = SQL_RE.search(record)
    if not match:
        return

    sql = match.group(1).strip()
    for reason in classify_sql(sql):
        emit_alert(reason, record)


def records(stream):
    buffer = []
    for line in stream:
        if RECORD_START.match(line) and buffer:
            yield "".join(buffer)
            buffer = [line]
        else:
            buffer.append(line)
    if buffer:
        yield "".join(buffer)


def main():
    print(f"[watcher] Watching PostgreSQL logs for user={VENDOR_USER}", flush=True)
    if ALLOWED_NETWORKS:
        print(f"[watcher] Source-IP expectations loaded: {len(ALLOWED_NETWORKS)}", flush=True)
    if WEBHOOK and not REPLAY_MODE:
        print("[watcher] Discord webhook alerts enabled", flush=True)
    elif REPLAY_MODE:
        print("[watcher] Replay mode: external and persistent alerts disabled", flush=True)
    else:
        print("[watcher] Terminal alerts only", flush=True)

    for record in records(sys.stdin):
        sys.stdout.write(record)
        sys.stdout.flush()
        analyze_record(record)


if __name__ == "__main__":
    main()
PY
  chmod +x "$LAB_DIR/monitor/watcher.py"
}

write_reference() {
  cat >"$LAB_DIR/TEST_PLAN.txt" <<'EOF_PLAN'
DATABASE VENDOR TEST PLAN

Purpose

Use a disposable PostgreSQL environment to evaluate how a third-party database
integration behaves without exposing production data or production credentials.

1. Run the lab only on infrastructure you control.

Use a disposable VM or VPS for any remote test. Do not expose the lab from a
corporate workstation, production server, VPN-connected machine, or host that
contains useful SSH keys, cloud credentials, API tokens, or unrelated secrets.

2. Use synthetic data only.

The shipped dataset contains synthetic customers, subscriptions, transactions,
API usage, and invoices. Do not import real customer or employer data.

3. Give the vendor only the dedicated test account.

Run:

    ./db_vendor_test_lab.sh creds

The vendor role receives CONNECT, schema USAGE, and SELECT on the approved test
tables. Database ownership, TEMP, write, DDL, role-management, and superuser
privileges are not granted.

4. Require encrypted transport.

The generated PostgreSQL configuration rejects plaintext TCP connections. The
vendor must use TLS, for example sslmode=require. The generated certificate is
self-signed and intended only for the disposable lab.

5. Restrict remote exposure outside Docker.

Before setting BIND_ADDR=0.0.0.0:

- ask the vendor for its outbound IP addresses or CIDRs;
- set ALLOWED_IPS to those values;
- configure the VPS or cloud-provider firewall to allow the database port only
  from those values;
- set FIREWALL_CONFIRMED=1;
- run ./db_vendor_test_lab.sh firewall and read the warning.

Do not rely on UFW alone for a Docker-published port. Docker's packet-filtering
rules can bypass UFW's normal path. Prefer the cloud-provider firewall or an
explicit DOCKER-USER policy on Linux.

6. Give the vendor a narrow assignment.

Example:

Build a dashboard showing revenue over time, transactions per day, top
customers, subscription distribution, API usage, and error rate.

7. Monitor while the test runs.

Run:

    ./db_vendor_test_lab.sh watch

The watcher records higher-signal deviations including write attempts, DDL,
privilege changes, attempts to disable read-only behavior, sensitive catalog
access, server-side file functions, canary access, authentication failures,
pg_hba rejections, and unexpected source IPs.

Normal BI metadata discovery is not treated as malicious by itself.

8. Canary object.

The lab contains internal_test.research_notes. It contains synthetic text only,
is outside the dashboard assignment, and is denied to the vendor role. An
attempt to access it is a signal to review. It is not conclusive proof of
malicious intent by itself.

9. Preserve evidence before teardown.

Run:

    ./db_vendor_test_lab.sh evidence

The evidence snapshot includes database logs, watcher alerts, redacted
configuration, project metadata when available, and SHA-256 hashes. The command
checks the evidence directory for the current lab secrets before reporting
success.

10. Destroy the lab.

Run:

    ./db_vendor_test_lab.sh destroy

Type DESTROY when prompted. The command removes the database volumes, .env, and
TLS private key. Delete the disposable VPS when the test is complete.

11. Boundary.

Do not scan, exploit, credential-stuff, disrupt, or access systems you do not
own or have explicit permission to test. This lab observes access intentionally
granted inside infrastructure you control.
EOF_PLAN
}

cmd_init() {
  require_base_tools

  if [[ -e "$ENV_FILE" ]]; then
    die "Lab already exists at $LAB_DIR. Destroy it first or set LAB_DIR to a new path."
  fi

  note "Creating lab at $LAB_DIR"
  mkdir -p "$LAB_DIR/init" "$LAB_DIR/monitor" "$LAB_DIR/evidence" "$LAB_DIR/config" "$LAB_DIR/tls"

  write_env
  load_env
  write_tls
  write_hba
  write_compose
  write_schema
  write_fake_data
  write_permissions

  # The container postgres user must read the bind-mounted init SQL.
  # LAB_DIR stays 0700 so other host users cannot reach it.
  chmod 700 "$LAB_DIR"
  chmod 755 "$LAB_DIR/init"
  chmod 644 "$LAB_DIR"/init/*.sql
  write_watcher
  write_reference

  cat >"$LAB_DIR/.gitignore" <<'EOF_IGNORE'
.env
tls/server.key
evidence/*
!evidence/.gitkeep
EOF_IGNORE
  touch "$LAB_DIR/evidence/.gitkeep"
  chmod 700 "$LAB_DIR/evidence"

  note "Lab created"
  printf '%s\n' \
    "Next:" \
    "  $0 start" \
    "  $0 creds" \
    "  $0 watch"
}

exposure_guard() {
  if [[ "$BIND_ADDR" == "127.0.0.1" || "$BIND_ADDR" == "::1" || "$BIND_ADDR" == "localhost" ]]; then
    return
  fi

  if [[ "${FORCE_EXPOSE:-0}" == "1" ]]; then
    printf 'WARNING: FORCE_EXPOSE=1 bypasses the remote-exposure guard.\n' >&2
    return
  fi

  [[ -n "${ALLOWED_IPS:-}" ]] || die "Remote bind refused: set ALLOWED_IPS first."
  [[ "${FIREWALL_CONFIRMED:-0}" == "1" ]] || die "Remote bind refused: configure the external firewall, then set FIREWALL_CONFIRMED=1."
}

set_vendor_password() {
  note "Applying vendor password after initialization"
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" exec -T \
      -e PGOPTIONS='-c log_statement=none' postgres \
      psql -v ON_ERROR_STOP=1 \
      -U "$ADMIN_USER" \
      -d "$DB_NAME" \
      -v vendor_password="$VENDOR_PASSWORD" \
      <<< "ALTER ROLE \"$VENDOR_USER\" PASSWORD :'vendor_password';" \
      >/dev/null
  )
}

cmd_start() {
  require_base_tools
  load_env
  exposure_guard

  note "Starting disposable PostgreSQL lab"
  if ! (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" up -d
  ); then
    (
      cd "$LAB_DIR"
      docker compose --env-file "$ENV_FILE" logs --no-color tls-init postgres >&2 || true
    )
    die "Docker Compose startup failed."
  fi

  note "Waiting for initialization to complete"
  local attempts=40
  while (( attempts-- > 0 )); do
    if (
      cd "$LAB_DIR"
      docker compose --env-file "$ENV_FILE" exec -T postgres \
        psql -U "$ADMIN_USER" -d "$DB_NAME" -Atqc \
        "SELECT 1 FROM pg_roles WHERE rolname = '$VENDOR_USER'" 2>/dev/null | grep -qx 1
    ); then
      set_vendor_password
      note "Database is ready"
      cmd_creds
      return
    fi
    sleep 2
  done

  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" logs --no-color tls-init postgres >&2 || true
  )
  die "PostgreSQL did not finish initialization. Run: $0 status"
}

cmd_creds() {
  load_env

  cat <<EOF_CREDS

VENDOR TEST CREDENTIALS

Host:     <LAB VPS HOSTNAME OR IP>
Port:     $DB_PORT
Database: $DB_NAME
Username: $VENDOR_USER
Password: $VENDOR_PASSWORD
TLS:      required (sslmode=require)

Approved tables:
  public.customers
  public.subscriptions
  public.transactions
  public.api_usage
  public.invoices

Do not send the administrator credentials to the vendor.

EOF_CREDS
}

cmd_watch() {
  require_base_tools
  load_env

  local replay=0
  if [[ "${1:-}" == "--replay" ]]; then
    replay=1
  elif [[ -n "${1:-}" ]]; then
    die "Unknown watch option: $1"
  fi

  mkdir -p "$LAB_DIR/evidence"
  touch "$LAB_DIR/evidence/alerts.log"
  chmod 600 "$LAB_DIR/evidence/alerts.log"

  note "Starting query watcher"

  if (( replay == 1 )); then
    printf 'Replay mode reads existing logs and does not send or persist alerts.\n\n'
    (
      cd "$LAB_DIR"
      docker compose --env-file "$ENV_FILE" logs --no-color --no-log-prefix postgres
    ) | env \
      VENDOR_USER="$VENDOR_USER" \
      DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
      ALLOWED_IPS="$ALLOWED_IPS" \
      REPLAY_MODE=1 \
      ALERT_LOG="" \
      python3 "$LAB_DIR/monitor/watcher.py"
    return
  fi

  printf 'Only new log entries are watched. Press Ctrl-C to stop watching.\n\n'
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" logs -f --tail 0 --no-color --no-log-prefix postgres
  ) | env \
    VENDOR_USER="$VENDOR_USER" \
    DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
    ALLOWED_IPS="$ALLOWED_IPS" \
    REPLAY_MODE=0 \
    ALERT_LOG="$LAB_DIR/evidence/alerts.log" \
    python3 "$LAB_DIR/monitor/watcher.py"
}

cmd_status() {
  require_base_tools
  load_env
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" ps
  )
}

hash_directory() {
  local dir="$1"
  if command -v shasum >/dev/null 2>&1; then
    (
      cd "$dir"
      # SHA256SUMS.txt is explicitly excluded from the input set.
      # shellcheck disable=SC2094
      find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 shasum -a 256 >SHA256SUMS.txt
    )
  elif command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$dir"
      # SHA256SUMS.txt is explicitly excluded from the input set.
      # shellcheck disable=SC2094
      find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS.txt
    )
  else
    die "Neither shasum nor sha256sum is available."
  fi
}

assert_no_secret_leak() {
  local dir="$1"
  local name value
  for name in ADMIN_PASSWORD VENDOR_PASSWORD DISCORD_WEBHOOK_URL; do
    value="${!name:-}"
    [[ -n "$value" ]] || continue
    if grep -R -F -l --exclude=SHA256SUMS.txt -- "$value" "$dir" >/dev/null 2>&1; then
      die "Evidence export contains $name. Review and remove the leaked value before sharing evidence."
    fi
  done

  if grep -R -F -l --exclude=SHA256SUMS.txt -- 'BEGIN PRIVATE KEY' "$dir" >/dev/null 2>&1; then
    die "Evidence export contains a private key."
  fi
}

cmd_evidence() {
  require_base_tools
  load_env

  local stamp out repo_root
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="$LAB_DIR/evidence/$stamp"
  mkdir -p "$out"
  chmod 700 "$out"

  note "Saving evidence snapshot to $out"

  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" logs --no-color --no-log-prefix postgres
  ) >"$out/postgres.log" 2>&1 || true

  if [[ -f "$LAB_DIR/evidence/alerts.log" ]]; then
    cp "$LAB_DIR/evidence/alerts.log" "$out/alerts.log"
  fi

  cp "$LAB_DIR/TEST_PLAN.txt" "$out/"
  cp "$LAB_DIR/docker-compose.yml" "$out/"
  cp "$LAB_DIR/config/pg_hba.conf" "$out/"
  cp "$LAB_DIR/init/01-schema.sql" "$out/"
  cp "$LAB_DIR/init/02-fake-data.sql" "$out/"
  cp "$LAB_DIR/init/03-permissions.sql" "$out/"
  cp "$LAB_DIR/tls/server.crt" "$out/"

  grep -Ev '^(ADMIN_PASSWORD|VENDOR_PASSWORD|DISCORD_WEBHOOK_URL)=' "$ENV_FILE" \
    >"$out/environment-redacted.txt"

  if repo_root="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"; then
    :
  else
    repo_root=""
  fi
  if [[ -n "$repo_root" ]] && git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    {
      printf 'commit='
      git -C "$repo_root" rev-parse HEAD
      printf 'status=\n'
      git -C "$repo_root" status --short
    } >"$out/repository-state.txt"
  fi

  assert_no_secret_leak "$out"
  hash_directory "$out"

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

cmd_firewall() {
  load_env
  cat <<EOF_FW
REMOTE EXPOSURE CHECKLIST

Current bind address: $BIND_ADDR
Current port:         $DB_PORT
Expected source IPs:  ${ALLOWED_IPS:-<not set>}

Preferred control:
Use the VPS or cloud-provider firewall and allow TCP/$DB_PORT only from the
vendor's documented outbound IP addresses or CIDRs.

Important:
Do not assume a UFW allow/deny rule protects a Docker-published port. Docker can
route published traffic through its own packet-filtering rules before UFW's
normal path.

On a Linux host that uses iptables, the DOCKER-USER chain is the Docker-provided
place for user filtering. Verify your platform before changing firewall rules.
Do not copy firewall commands blindly into a remote host because a bad rule can
lock you out.

After the external firewall is verified:
1. Set ALLOWED_IPS in .env.
2. Set BIND_ADDR=0.0.0.0 only if remote access is required.
3. Set FIREWALL_CONFIRMED=1.
4. Run: $0 start

FORCE_EXPOSE=1 bypasses the script guard and should normally remain disabled.
EOF_FW
}

cmd_destroy() {
  require_base_tools
  load_env

  local confirmation="${1:-}"
  if [[ "$confirmation" != "--yes" ]]; then
    printf '\nThis permanently removes the PostgreSQL containers and lab volumes.\n'
    printf 'Evidence under %s is left in place.\n\n' "$LAB_DIR/evidence"
    printf 'Type DESTROY to continue: '
    IFS= read -r confirmation
    [[ "$confirmation" == "DESTROY" ]] || die "Destroy cancelled."
  fi

  note "Destroying database and TLS volumes"
  (
    cd "$LAB_DIR"
    docker compose --env-file "$ENV_FILE" down -v --remove-orphans
  )

  rm -f "$LAB_DIR/.env" "$LAB_DIR/tls/server.key"
  note "Database destroyed and lab secrets removed"
  printf 'Delete the disposable VPS when the test is finished.\n'
}

cmd_plan() {
  if [[ -f "$LAB_DIR/TEST_PLAN.txt" ]]; then
    cat "$LAB_DIR/TEST_PLAN.txt"
  else
    printf 'Run: %s init\n' "$0"
  fi
}

usage() {
  cat <<EOF_USAGE
Usage:
  $0 init             Create the disposable lab files
  $0 start            Start PostgreSQL and initialize fake data
  $0 creds            Print the vendor test credentials
  $0 watch            Watch only new queries and alert on deviations
  $0 watch --replay   Review existing logs without sending/persisting alerts
  $0 status           Show container status
  $0 firewall         Print the remote-exposure checklist
  $0 evidence         Save and hash a redacted evidence snapshot
  $0 stop             Stop the lab without deleting data
  $0 destroy          Delete containers, volumes, and lab secrets
  $0 destroy --yes    Non-interactive destroy for CI/test automation
  $0 plan             Print the generated test plan

Default lab directory:
  $LAB_DIR

Override it with:
  LAB_DIR=/path/to/lab $0 init

Recommended sequence:
  init -> firewall (if remote) -> start -> creds -> watch -> evidence -> destroy
EOF_USAGE
}

case "${1:-}" in
  init)     cmd_init ;;
  start)    cmd_start ;;
  creds)    cmd_creds ;;
  watch)    cmd_watch "${2:-}" ;;
  status)   cmd_status ;;
  firewall) cmd_firewall ;;
  evidence) cmd_evidence ;;
  stop)     cmd_stop ;;
  destroy)  cmd_destroy "${2:-}" ;;
  plan)     cmd_plan ;;
  -h|--help|help|"") usage ;;
  *) die "Unknown command: $1. Run: $0 --help" ;;
esac
