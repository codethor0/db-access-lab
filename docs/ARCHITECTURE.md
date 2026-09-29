# Architecture

`db-access-lab` is a disposable PostgreSQL test environment for evaluating a
third-party product that requests database access.

The repository ships one operator script. `init` generates a self-contained lab
under a local lab directory. The generated environment contains PostgreSQL,
synthetic fixtures, a dedicated vendor role, TLS material, a strict pg_hba
policy, a query watcher, and an evidence directory.

## Trust boundaries

The vendor is untrusted.

The vendor receives only a dedicated database username and password. The role
is granted CONNECT, schema USAGE, and SELECT on approved synthetic tables. The
role does not receive ownership, TEMP, write, DDL, role-management, database
creation, or superuser privileges.

The PostgreSQL permission model is the enforcement boundary. The watcher is an
observation layer and is not used as an authorization control.

The Docker host is trusted by the operator but should be disposable for remote
tests. The lab must not share production credentials, production data, or
unrelated secrets with the container environment.

## Network model

PostgreSQL binds to loopback by default. Plaintext TCP is rejected by pg_hba.
Remote exposure requires an explicit bind change, expected vendor source
addresses, and operator confirmation that an external firewall has been
configured.

The project does not automatically modify the host firewall. Cloud-provider or
VPS firewall rules are preferred because Docker-published ports can bypass
common UFW paths.

## Observation model

PostgreSQL logs connections, disconnections, statements, durations, and errors.
The watcher classifies higher-signal deviations and can optionally send live
notifications to a Discord webhook.

Normal metadata discovery is expected from BI software. The watcher therefore
focuses on write attempts, DDL, privilege manipulation, read-write overrides,
sensitive catalogs, server-side file functions, canary access, failed
authentication, pg_hba rejection, and unexpected source addresses.

## Evidence model

Evidence export copies logs and non-secret configuration into a timestamped
directory, records repository state when available, checks the output for the
current lab secrets, and creates a SHA-256 manifest.

This is an investigation aid. It is not represented as a certified forensic
chain-of-custody system.
