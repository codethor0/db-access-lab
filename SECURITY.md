# Security Policy

## Supported versions

Until the first tagged release, only the latest commit on `main` is supported.
After tagged releases begin, this section will identify supported release lines.

## Reporting a vulnerability

Use GitHub Private Vulnerability Reporting from the repository Security tab.
Do not open a public issue for an unresolved vulnerability.

Include, when available:

- affected commit or version;
- operating system and Docker version;
- steps to reproduce;
- expected and observed behavior;
- security impact;
- logs or evidence with all real secrets removed.

Reports are acknowledged as soon as practical. Public disclosure should wait
until a fix or coordinated mitigation is available.

## Scope

Security reports are especially useful for issues involving:

- privilege boundaries;
- database role permissions;
- TLS enforcement;
- remote exposure defaults;
- secret handling;
- evidence redaction;
- watcher bypass or unsafe parsing;
- Docker isolation;
- CI or supply-chain controls;
- teardown leaving active credentials or data behind.

Do not place real credentials, production data, or third-party confidential
information in a vulnerability report.
