# Changelog

All notable project changes are documented here.

The project follows Semantic Versioning once tagged releases begin.

## Unreleased

## [0.1.1] - 2026-09-29

### Security

- Alert on pg_hba connection rejections (for example a vendor connecting without TLS).
- Detect role enumeration via pg_roles and pg_user as sensitive catalog access.

## [0.1.0] - 2026-09-29

### Security

- Hardened the disposable PostgreSQL lab around TLS-only vendor TCP access.
- Removed vendor passwords from generated initialization SQL.
- Revoked default PUBLIC database privileges from the vendor test database.
- Added remote-exposure guards and explicit firewall guidance.
- Added source-IP expectation monitoring.
- Added alerts for authentication failures, pg_hba rejections, privilege
  changes, read-write overrides, sensitive catalog access, file functions, and
  canary access.
- Added redacted evidence export with secret-leak checks and SHA-256 manifests.

### Testing

- Added shell syntax and ShellCheck gates.
- Added watcher classification regression tests.
- Added Docker end-to-end tests for TLS, least privilege, canary denial,
  evidence export, and teardown.
