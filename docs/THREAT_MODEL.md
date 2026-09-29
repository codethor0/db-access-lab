# Threat Model

## Assets

- Docker host
- Disposable PostgreSQL instance
- Lab credentials
- Synthetic dataset
- Evidence logs
- Optional notification webhook
- Source repository
- CI token and workflow context
- Release artifacts

## Threat actors

- Malicious or compromised third-party vendor
- Opportunistic internet scanner
- Malicious contributor
- Compromised dependency or GitHub Action
- Operator misconfiguration

## Primary threats and controls

### Production data or credential exposure

Control: the project ships synthetic fixtures only and documents a disposable
host model. No production import path is required for normal operation.

### Excessive database privilege

Control: PUBLIC database privileges are revoked. The vendor role receives only
CONNECT, schema USAGE, and SELECT on named tables. CI verifies that SELECT works
while write, TEMP creation, and canary access fail.

### Plaintext credential transport

Control: vendor TCP access is accepted only through hostssl rules. CI verifies
that `sslmode=require` succeeds and `sslmode=disable` fails.

### Unrestricted public database exposure

Control: loopback is the default bind. Remote bind is refused unless expected
source addresses are configured and the operator confirms an external firewall
has been applied. Documentation warns that UFW alone may not cover Docker
published ports.

### Secret leakage into generated files or evidence

Control: vendor passwords are applied after database initialization and are not
written into initialization SQL. Evidence export redacts environment secrets,
excludes the TLS private key, and scans the export for current secret values.

### Scope deviation by the vendor

Control: least-privilege grants block access outside the approved tables. Logs
and watcher alerts surface denied access, canary access, privilege manipulation,
write attempts, and other high-signal behavior.

### Resource exhaustion

Control: the vendor role has a connection limit and statement, lock, and idle
transaction timeouts. Operators should also use host-level CPU and memory
controls when exposing the lab to an untrusted service.

### CI supply-chain compromise

Control: workflow permissions are read-only and the checkout action is pinned
to a full commit SHA. New workflow dependencies require review under the
project doctrine.

### False interpretation of alerts

Control: documentation states that alerts are signals, not proof of malicious
intent. Normal BI metadata discovery is not treated as malicious by itself.

### Incomplete teardown

Control: destroy removes containers, Docker volumes, `.env`, and the TLS private
key. CI verifies that secret files are absent after teardown.
