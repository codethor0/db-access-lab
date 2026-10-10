# Testing

Testing must verify security controls, not only startup.

## Static checks

Run:

    bash -n scripts/db_vendor_test_lab.sh
    shellcheck scripts/db_vendor_test_lab.sh tests/*.sh
    ./tests/psql_regression.sh

The psql regression test fails if a `psql -c` command references a `:'var'` or
`:"var"` variable (psql does not interpolate variables in `-c`), or if a secret
is passed with `-v name=...` or a conninfo `password=...`, where it would be
visible in the process argument list.

## Watcher regression test

Initialize a temporary lab, then run the watcher smoke test:

    export LAB_DIR="$(mktemp -d)/db-lab"
    ./scripts/db_vendor_test_lab.sh init
    ./tests/watcher_smoke.sh

The test verifies expected alerts while keeping normal BI queries such as
EXTRACT, CTEs, and information_schema discovery quiet.

## Docker end-to-end

Run on a disposable machine with Docker Compose v2:

    export RUNNER_TEMP="$(mktemp -d)"
    ./tests/e2e.sh

The E2E test verifies:

- initialization completes;
- TLS database access succeeds;
- plaintext database access fails;
- approved SELECT succeeds;
- UPDATE fails;
- canary access fails;
- TEMP table creation fails;
- high-signal watcher alerts are produced;
- evidence export creates a SHA-256 manifest;
- no lab password appears in any docker or psql process argument list;
- destroy removes `.env` and the TLS private key.

The test creates and destroys Docker volumes. Do not point `LAB_DIR` at an
existing lab that contains evidence you intend to keep.

## Clean-clone release check

Before a release, perform the Docker E2E from a clean clone on a disposable
host. Do not release from a known failing CI run.
