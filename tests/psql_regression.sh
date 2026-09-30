#!/usr/bin/env bash
# Static guard for two psql mistakes:
#   1. psql -c does not interpolate :'var' or :"var", so such a command sends
#      the literal text to the server and fails.
#   2. A secret passed with -v name=... or a conninfo password=... sits in the
#      process argument list, where other local users can read it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check() {
  python3 - "$@" <<'EOF_PY'
import re
import sys

FLAG_C = re.compile(r"(?:^|\s)-[A-Za-z]*c(?:\s|$)")
PSQL_VAR = re.compile(r":'[A-Za-z_]\w*'|:\"[A-Za-z_]\w*\"")
SECRET_ARG = re.compile(r"""(?:-v\s+[A-Za-z_]\w*=|--set[=\s][A-Za-z_]\w*=|\bpassword=)["']?\$""", re.I)


def strip_quoted(text):
    return re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", "''", text)


def logical_lines(path):
    start, buf = 0, []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            if not buf:
                start = number
            if line.endswith("\\"):
                buf.append(line[:-1])
                continue
            buf.append(line)
            yield start, " ".join(buf)
            buf = []
    if buf:
        yield start, " ".join(buf)


failures = []
for path in sys.argv[1:]:
    for number, line in logical_lines(path):
        if line.lstrip().startswith("#"):
            continue
        if "psql" in line and FLAG_C.search(strip_quoted(line)) and PSQL_VAR.search(line):
            failures.append(f"{path}:{number}: psql -c cannot interpolate {PSQL_VAR.search(line).group(0)}")
        if SECRET_ARG.search(line):
            failures.append(f"{path}:{number}: secret passed in a process argument")

for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(1 if failures else 0)
EOF_PY
}

# The guard must reject known-bad commands before its pass on the repo means anything.
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

cat >"$fixtures/single-quoted.sh" <<'EOF_FIXTURE'
psql -U admin -d lab \
  -c "ALTER ROLE \"$VENDOR_USER\" PASSWORD :'vendor_password';"
EOF_FIXTURE
cat >"$fixtures/double-quoted.sh" <<'EOF_FIXTURE'
psql -Atqc 'SELECT 1 FROM pg_roles WHERE rolname = :"role"'
EOF_FIXTURE
cat >"$fixtures/secret-var.sh" <<'EOF_FIXTURE'
psql -v vendor_password="$VENDOR_PASSWORD" <<< "SELECT 1"
EOF_FIXTURE
cat >"$fixtures/secret-conninfo.sh" <<'EOF_FIXTURE'
conn="host=127.0.0.1 password=$VENDOR_PASSWORD"
EOF_FIXTURE

for fixture in "$fixtures"/*.sh; do
  if check "$fixture" 2>/dev/null; then
    echo "psql regression guard missed $(basename "$fixture")" >&2
    exit 1
  fi
done

targets=()
for file in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
  # This file holds the bad fixtures on purpose.
  [[ "$file" -ef "${BASH_SOURCE[0]}" ]] || targets+=("$file")
done
check "${targets[@]}"
echo 'psql regression test: PASS'
