# Contributing

Contributions are welcome when they preserve the project's security model.

## Rules

Keep changes small and focused. Do not combine unrelated refactors, dependency
changes, security changes, and new features in one pull request unless they are
inseparable.

Security controls must not be weakened to make a test pass or simplify a demo.
Safe defaults are requirements.

Do not submit production data, real credentials, private evidence, employer
material, customer information, assistant transcripts, prompt files, or local
secrets.

Do not add dependencies unless the need is clear and the dependency has been
reviewed for maintenance status, license, and security impact.

No emojis or decorative Unicode are used in code or project documentation.

## Before opening a pull request

Run:

    bash -n scripts/db_vendor_test_lab.sh
    shellcheck scripts/db_vendor_test_lab.sh tests/*.sh
    ./tests/psql_regression.sh

Then run the watcher smoke test and Docker E2E as documented in
`docs/TESTING.md`.

Every behavior change should include a test when practical. Every security bug
fix should include a regression test when practical.

## Security vulnerabilities

Do not open a public issue for an unresolved vulnerability. Follow
`SECURITY.md` and use GitHub Private Vulnerability Reporting.
