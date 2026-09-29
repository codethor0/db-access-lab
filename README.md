# db-access-lab

Disposable PostgreSQL lab for evaluating third-party products that request
database access.

The lab provides synthetic data, a dedicated least-privilege vendor role,
TLS-only vendor TCP access, query and connection logging, deviation alerts,
evidence export, and clean teardown.

This is a defensive tool. It does not scan, exploit, or access the vendor's
systems.

## Safety first

Use a disposable VM or VPS for any remote test. Do not use production data,
production credentials, a corporate workstation, a production server, or a
VPN-connected host.

PostgreSQL binds to `127.0.0.1` by default. Remote exposure is an explicit
operator action.

Read `docs/SAFETY.md` before exposing the database to a third party.

## Requirements

- Bash
- Docker with Compose v2
- Python 3
- OpenSSL

## Quick start

    ./scripts/db_vendor_test_lab.sh init
    ./scripts/db_vendor_test_lab.sh start
    ./scripts/db_vendor_test_lab.sh creds
    ./scripts/db_vendor_test_lab.sh watch

When the test is complete:

    ./scripts/db_vendor_test_lab.sh evidence
    ./scripts/db_vendor_test_lab.sh destroy

## Remote vendor access

Ask the vendor for the outbound IP addresses or CIDRs used by its database
connector.

Then read:

    ./scripts/db_vendor_test_lab.sh firewall

Configure the VPS or cloud-provider firewall before changing `BIND_ADDR` from
loopback. Docker-published ports can bypass common UFW paths, so do not use UFW
as the only control without verifying the effective packet-filtering path.

The vendor must use TLS. The credentials command prints the connection details
and indicates `sslmode=require`. The generated certificate is self-signed.
`sslmode=require` encrypts transport but does not verify server identity. If the
vendor supports CA pinning, provide `tls/server.crt` and use certificate
verification appropriate to the client.

## What is monitored

The watcher focuses on higher-signal deviations, including:

- write attempts;
- DDL;
- privilege manipulation;
- read-write overrides;
- sensitive PostgreSQL catalog access;
- server-side file functions;
- canary access;
- authentication failures;
- pg_hba rejections;
- unexpected source addresses.

Normal BI metadata discovery is not treated as malicious by itself.

## Evidence

`evidence` saves PostgreSQL logs, watcher alerts, redacted configuration,
repository state when available, and SHA-256 hashes. It checks the export for
the current lab secrets before reporting success.

## Documentation

- `DOCTRINE.md`: engineering and security rules
- `docs/ARCHITECTURE.md`: architecture and trust boundaries
- `docs/THREAT_MODEL.md`: threats and controls
- `docs/TESTING.md`: local and CI validation
- `docs/SAFETY.md`: safe-use boundaries
- `CONTRIBUTING.md`: contribution rules
- `SECURITY.md`: vulnerability reporting

## License

Apache License 2.0. See `LICENSE`.
