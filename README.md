# db-access-lab

Disposable PostgreSQL lab for testing third-party products that ask for
database access. It gives the vendor a TLS-only, SELECT-only account on
synthetic data, logs every connection and query, alerts on anything outside
the agreed scope, and saves hashed evidence before teardown.

This is a defensive tool. It never touches the vendor's systems.

## Quick start

Requirements: Docker with Compose v2, Python 3, openssl, Bash.

    ./scripts/db_vendor_test_lab.sh init
    ./scripts/db_vendor_test_lab.sh start
    ./scripts/db_vendor_test_lab.sh watch

When finished:

    ./scripts/db_vendor_test_lab.sh evidence
    ./scripts/db_vendor_test_lab.sh destroy

Run it on a disposable VPS, not a workstation. PostgreSQL binds to 127.0.0.1
until you explicitly expose it. Docker bypasses UFW; read
`./scripts/db_vendor_test_lab.sh firewall` before exposing the port.

The full walk-through is generated at init and printed by
`./scripts/db_vendor_test_lab.sh plan`. Project rules are in DOCTRINE.md.

## License

Apache License 2.0. See LICENSE.
