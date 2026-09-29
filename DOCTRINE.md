# DB Vendor Lab Engineering Doctrine

Version: 0.1
Status: Project doctrine
Owner: CodeThor
Scope: Public open-source defensive database-access validation lab

## 1. Purpose

This project exists to give researchers, developers, and small teams a fast, reproducible, disposable environment for evaluating third-party products that request database access.

The lab must make it possible to:

- expose synthetic data instead of production data;
- give a third party only the minimum database permissions required for a stated task;
- observe authentication, connection, query, and permission behavior;
- detect activity that deviates from the agreed scope;
- preserve useful evidence;
- revoke access and destroy the environment cleanly;
- reproduce the same test from a clean clone.

This project is defensive. It is not an exploitation framework, offensive toolkit, credential-harvesting system, or platform for accessing infrastructure that the user does not own or have explicit permission to test.

## 2. Core engineering rule

Security controls are requirements, not obstacles.

Never weaken authentication, authorization, isolation, validation, logging, evidence handling, tests, or safe defaults to make a feature work or to make a test pass.

If a feature conflicts with a security invariant, change or remove the feature.

## 3. Non-negotiable project rules

1. No production data.
2. No production credentials.
3. No reused credentials.
4. No hidden network exposure.
5. No privileged containers unless a documented requirement makes it unavoidable.
6. No Docker socket mounted into application containers.
7. No host PID, host IPC, or host network mode by default.
8. No root database account provided to a test subject.
9. No database owner, superuser, CREATE, ALTER, DROP, INSERT, UPDATE, or DELETE permissions unless a specific test explicitly requires them.
10. No secrets committed to Git.
11. No secrets embedded in container images.
12. No credentials printed into CI logs.
13. No telemetry, analytics, tracking, or external callbacks unless the user explicitly enables them.
14. No real customer, employer, or third-party confidential information in fixtures, screenshots, logs, examples, or documentation.
15. No employer branding or proprietary content.
16. No AI-tool attribution, generated-by banners, assistant transcripts, prompt files, or build-tool metadata in the public repository.
17. No false authorship claims. Git authorship must represent the person making the commit. Required third-party attribution and license notices must be preserved.
18. No emojis in code, comments, documentation, logs, commit messages, or project UI.
19. Use ASCII-only code, comments, documentation, logs, and generated terminal output unless a functional requirement explicitly requires Unicode.
20. No known failing tests or known release-blocking defects at release time.

## 4. Safe-by-default architecture

The default configuration must be safe before the user changes anything.

The default lab must:

- bind database services to loopback only;
- use synthetic data only;
- generate dedicated test credentials;
- restrict the test account to approved schemas and tables;
- force read-only behavior at both privilege and session levels where supported;
- enable useful audit logging;
- avoid automatic internet exposure;
- require an explicit configuration change before remote access is possible;
- make teardown obvious and reliable.

Internet exposure must be an explicit action.

If remote access is required, documentation must require:

- a disposable VM or VPS;
- a host or cloud firewall;
- source-IP allowlisting where the vendor can provide egress addresses;
- encrypted transport;
- no unrelated services on the host;
- no corporate VPN connection;
- no useful SSH keys, cloud tokens, API keys, or unrelated credentials on the host.

## 5. Isolation doctrine

Treat the test subject as untrusted.

The lab must assume the third party may:

- enumerate schemas;
- inspect metadata;
- attempt writes;
- probe permissions;
- attempt privilege changes;
- access unrelated tables;
- attempt expensive queries;
- reconnect from unexpected addresses;
- retry failed authentication;
- trigger parser and logging edge cases.

The environment must remain safe even when these actions occur.

Isolation controls should include, where practical:

- disposable host;
- dedicated Docker network;
- no host network mode;
- no Docker daemon socket;
- no unnecessary bind mounts;
- no mounts containing source credentials;
- non-root application containers;
- minimal Linux capabilities;
- default seccomp protections;
- read-only container filesystems where the component supports them;
- writable named volumes only where required;
- CPU, memory, PID, and connection limits;
- database statement timeouts;
- idle transaction timeouts;
- connection limits;
- explicit teardown.

The database itself is the enforcement boundary. Monitoring is not a substitute for authorization.

## 6. Database authorization doctrine

Every external test subject receives a dedicated account.

The account must:

- be unique to the test;
- use a unique generated password or equivalent secret;
- have a short lifetime;
- have only the permissions needed for the stated task;
- be independently revocable;
- have a connection limit;
- have timeouts applied;
- use a restricted search path where supported;
- have no ownership privileges;
- have no role-management privileges;
- have no database-creation privileges;
- have no superuser privileges.

For a dashboard test, the normal baseline is:

- CONNECT to one test database;
- USAGE on one approved schema;
- SELECT on explicitly approved tables or views.

Do not use blanket permissions when an explicit allowlist is practical.

Test the restrictions. Do not assume the grants and revocations are correct because the configuration looks correct.

## 7. Synthetic data doctrine

All shipped fixtures must be synthetic.

Synthetic data must not be copied, transformed, sampled, or lightly anonymized from real customer or employer data.

Use reserved or clearly non-routable example values where possible.

Synthetic fixtures should be realistic enough to exercise:

- joins;
- aggregates;
- time-series dashboards;
- filtering;
- grouping;
- error-rate calculations;
- schema discovery;
- normal BI metadata queries.

Synthetic data should not include secrets that resemble valid production credentials.

## 8. Canary doctrine

Canary objects may be used to detect scope deviation.

A canary must:

- contain synthetic data only;
- never contain a real secret;
- be unrelated to the stated dashboard task;
- be denied to the external test account by default;
- generate a clear alert when accessed or requested;
- be documented for the lab operator;
- not be represented as conclusive proof of malicious intent by itself.

A canary is an observation point, not bait for inducing illegal behavior.

## 9. Logging doctrine

Logs are evidence.

The lab should capture, where supported:

- UTC timestamp;
- database;
- username or role;
- application name;
- source IP and source port;
- connection;
- disconnection;
- authentication failures;
- permission failures;
- executed statement or normalized query information;
- duration;
- database errors.

Logs must not intentionally capture passwords, connection strings containing secrets, webhook secrets, private keys, or unrelated host secrets.

If full statement logging is enabled, the documentation must state that it is intended for synthetic lab data only.

Logs should be easy to export before teardown.

## 10. Alerting doctrine

Alerts must focus on behavior that materially deviates from the agreed task.

High-signal events include:

- write attempts;
- DDL attempts;
- privilege changes;
- access to denied schemas;
- access to canary objects;
- unexpected source IPs;
- repeated authentication failures;
- server-side file access functions;
- role switching;
- access to sensitive authorization catalogs;
- attempts to create extensions;
- unusually expensive or long-running queries;
- connection patterns outside the expected test window.

Normal BI behavior often includes metadata discovery.

Do not treat ordinary queries against information_schema, documented pg_catalog views, SHOW, SET, prepared-statement setup, or driver capability checks as malicious by default.

Alerting logic must distinguish metadata discovery from real scope deviation.

Do not let heuristic alerting make security decisions that belong in database permissions or the host firewall.

## 11. Evidence doctrine

Evidence collection must be deterministic and safe.

The evidence command should preserve:

- database logs;
- application or watcher logs;
- redacted configuration;
- exact project version;
- exact Git commit SHA;
- container image identifiers;
- timestamps;
- test scope;
- approved tables;
- allowed source addresses if configured;
- test account name;
- hashes of collected evidence files.

Evidence exports must exclude:

- database passwords;
- webhook secrets;
- private keys;
- reusable tokens;
- unrelated host configuration;
- unrelated user data.

Use SHA-256 or stronger hashes for evidence manifests.

Do not claim forensic chain-of-custody guarantees unless the project actually implements and documents them.

## 12. Failure behavior

Fail closed.

Examples:

- If a required security setting cannot be applied, startup should fail.
- If an allowlist is malformed, do not silently fall back to allow-all.
- If a secret file has unsafe permissions, warn clearly or stop.
- If initialization is partial, do not report success.
- If a test database cannot enforce the intended role permissions, do not present the environment as ready.
- If Docker or another required runtime is missing, stop with a precise error.
- If evidence collection fails, report which artifacts were not collected.

Never convert a security failure into a warning merely to keep the demo running.

## 13. Input handling

Treat all external input as untrusted.

Validate:

- environment variables;
- port values;
- IP and CIDR inputs;
- hostnames;
- file paths;
- webhook URLs;
- database identifiers;
- usernames;
- configuration file values;
- command-line arguments.

Rules:

- quote shell variables;
- avoid eval;
- avoid shell construction from untrusted strings;
- avoid command injection paths;
- use strict shell mode where appropriate;
- use parameterized SQL for dynamic values;
- avoid interpolating identifiers unless they are validated against a strict allowlist;
- use safe temporary-file creation;
- use restrictive file permissions for secrets.

## 14. Shell doctrine

Shell code must be small, readable, and defensive.

Required practices:

- use `set -euo pipefail` where compatible with the script design;
- quote expansions;
- use functions for repeated operations;
- validate dependencies before changing state;
- produce actionable error messages;
- avoid silent failures;
- avoid parsing fragile human-readable output when a machine-readable form exists;
- use `mktemp` for temporary files;
- clean up temporary artifacts;
- make destructive operations explicit;
- keep initialization idempotent where practical;
- verify results after state-changing operations.

Required checks for shipped shell code:

- `bash -n`;
- ShellCheck;
- functional tests for critical paths.

## 15. Python or other watcher code

If the project includes Python or another runtime:

- use the standard library where practical;
- minimize third-party packages;
- pin and lock required dependencies;
- validate untrusted log content;
- bound memory and queue growth;
- use network timeouts;
- handle malformed input without terminating the monitor;
- do not execute content taken from logs;
- do not deserialize unsafe formats;
- redact secrets before output;
- test alert classification separately from live I/O.

For Python, use automated formatting/linting and unit tests appropriate to the project.

## 16. Docker doctrine

Use Docker to improve reproducibility and isolation, not to create a false sense of security.

Container rules:

- prefer Docker Official Images or verified trusted publishers;
- use minimal images;
- do not use `latest`;
- pin release images to reviewed versions and, for release reproducibility, immutable digests where practical;
- update pinned images deliberately and regularly;
- run application containers as non-root where practical;
- never use `--privileged` for normal operation;
- do not mount `/var/run/docker.sock`;
- do not use host PID, host IPC, or host network by default;
- drop unnecessary Linux capabilities;
- keep default seccomp protections;
- use read-only filesystems where practical;
- mount only required writable volumes;
- configure health checks;
- configure restart behavior intentionally;
- apply resource limits appropriate to the runtime;
- keep secrets out of Dockerfiles and image layers;
- do not publish unnecessary ports;
- bind sensitive services to loopback by default.

Rootless Docker is preferred when it fits the deployment environment.

## 17. Dependency doctrine

Every dependency increases attack surface.

Before adding a dependency:

1. prove the standard library or existing project code cannot reasonably solve the need;
2. verify the project is actively maintained;
3. inspect its security history and open issues;
4. review its license;
5. review its OpenSSF Scorecard or equivalent signals when available;
6. pin or lock the version;
7. document why it is needed.

Do not add a dependency for convenience when a small, auditable implementation is safer.

Remove unused dependencies immediately.

Automate dependency update visibility with Dependabot, Renovate, or an equivalent service.

## 18. Source control doctrine

Git is part of the security boundary.

Repository rules:

- `main` is the only long-lived branch unless the project later has a documented release need;
- changes after bootstrap flow through pull requests;
- required CI checks must pass before merge;
- conversations must be resolved before merge;
- use signed commits where practical;
- use signed or attested release artifacts;
- protect `main` from force pushes and deletion;
- protect release tags;
- prefer linear history;
- do not bypass failed checks to save time;
- do not rewrite published release history.

For a solo-maintainer repository, do not create an impossible review policy. Automated checks are mandatory. Human review becomes mandatory once a trusted second maintainer is available for security-sensitive changes.

## 19. GitHub Actions doctrine

CI workflows execute privileged automation and must be treated as code.

Rules:

- declare explicit minimum `permissions`;
- default `GITHUB_TOKEN` permissions to read-only where possible;
- pin third-party actions to full-length commit SHAs;
- verify pinned actions come from the intended repository;
- do not run untrusted pull-request code with write tokens or repository secrets;
- do not use `pull_request_target` with checkout/execution of untrusted PR code unless the threat model is fully understood;
- do not print secrets;
- avoid persistent cloud credentials;
- prefer short-lived OIDC credentials if cloud access is ever required;
- review workflow changes as security-sensitive changes;
- lint workflows;
- keep release workflows separate from ordinary PR validation.

## 20. CI minimum gate

Every pull request should run the checks relevant to the files in the project.

Baseline gate:

- syntax validation;
- linting;
- unit tests;
- negative permission tests;
- Docker build or Compose validation;
- disposable end-to-end startup;
- health check;
- read-only account verification;
- approved SELECT succeeds;
- INSERT fails;
- UPDATE fails;
- DELETE fails;
- CREATE fails;
- canary access fails;
- evidence export succeeds;
- teardown succeeds;
- secret scan;
- dependency review;
- container or dependency vulnerability scan;
- workflow lint;
- documentation link or consistency checks where practical.

A release must not be cut from a failing CI run.

## 21. Clean-clone doctrine

A project that only works on the maintainer's machine is not ready.

Before release, validate from a clean environment:

1. clone the repository;
2. read only the documented prerequisites;
3. run the documented setup command;
4. start the lab;
5. validate synthetic data exists;
6. validate the vendor account permissions;
7. run the monitor;
8. trigger known-safe positive and negative tests;
9. export evidence;
10. destroy the lab;
11. confirm no unexpected state remains.

The README must be sufficient to complete this process without undocumented maintainer knowledge.

## 22. Security testing doctrine

Test the controls, not just the happy path.

At minimum test:

- correct startup;
- repeated startup;
- malformed configuration;
- missing dependency;
- unsafe file permissions;
- wrong password;
- write attempts;
- DDL attempts;
- canary access;
- unrelated schema access;
- long-running query timeout;
- connection limit;
- teardown;
- evidence redaction;
- secret absence from Git history and artifacts;
- remote exposure defaults;
- firewall guidance;
- unexpected watcher input;
- malformed log lines;
- watcher restart behavior.

Every fixed security bug should receive a regression test when practical.

## 23. Static analysis and security automation

Use automation to catch repeatable mistakes.

Recommended public-repository controls:

- GitHub secret scanning;
- push protection where available;
- dependency graph;
- Dependabot alerts and update PRs;
- dependency review;
- code scanning for supported languages;
- OpenSSF Scorecard;
- container scanning;
- ShellCheck;
- workflow linting;
- language-specific static analysis.

Automation does not replace manual review.

## 24. Supply-chain doctrine

The project should be verifiable by consumers.

As the project matures:

- generate an SBOM for release artifacts using SPDX or CycloneDX;
- publish cryptographic checksums;
- generate build provenance;
- use GitHub artifact attestations or Sigstore-compatible attestations;
- sign container images or release artifacts when distributed;
- work toward applicable SLSA 1.2 Source and Build controls;
- work toward an OpenSSF Best Practices or OSPS Baseline badge;
- track and improve OpenSSF Scorecard findings.

Do not claim a compliance level that has not been verified.

## 25. Repository contents

The public repository should contain only material needed to build, test, understand, operate, audit, or contribute to the project.

Recommended baseline:

- `README.md`
- `LICENSE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `CHANGELOG.md`
- `DOCTRINE.md`
- `docs/ARCHITECTURE.md`
- `docs/THREAT_MODEL.md`
- `docs/TESTING.md`
- `docs/SAFETY.md`
- `.gitignore`
- `.editorconfig`
- source and scripts
- tests
- synthetic fixtures
- Docker and Compose files
- GitHub Actions workflows
- dependency update configuration

Add `CODE_OF_CONDUCT.md` when the repository begins accepting broader community participation.

## 26. Files that must not be published

Do not commit:

- `.env`;
- passwords;
- API keys;
- webhooks;
- tokens;
- private keys;
- real database dumps;
- customer data;
- employer data;
- local evidence bundles;
- packet captures from real environments;
- editor caches;
- OS metadata;
- generated build artifacts;
- personal shell history;
- AI assistant transcripts;
- prompt files;
- assistant-specific configuration;
- generated-by metadata;
- private research notes;
- screenshots containing real credentials;
- temporary exports.

The `.gitignore` must cover project-specific generated and sensitive files.

Before the first public push, inspect both the working tree and Git history for secrets.

## 27. Authorship and project identity

The repository is published under the CodeThor GitHub identity.

Rules:

- configure local Git identity intentionally;
- verify the authenticated GitHub account before creating or pushing the public repository;
- do not add AI systems or coding assistants as Git co-authors;
- do not add generated-by headers;
- do not publish assistant prompts or session artifacts;
- do not include vendor-specific assistant configuration in the repository;
- do not make statements claiming the project was created without tools;
- preserve required attribution for third-party code and dependencies;
- keep copyright, license, and contributor information accurate.

The public repository should describe the project, its maintainers, its security model, and its contributors. It does not need to document private development tooling that is irrelevant to users.

## 28. Documentation doctrine

Documentation is part of the product.

Documentation must be:

- accurate;
- concise;
- executable as written;
- free of marketing claims that cannot be proven;
- explicit about safety boundaries;
- explicit about defaults;
- explicit about destructive commands;
- explicit about what evidence does and does not prove.

Do not document a feature before it exists.

Do not leave stale commands after implementation changes.

Every release should include a documentation review.

No emojis. No decorative Unicode. No filler.

## 29. README minimum

The README should answer, in this order:

1. What is this?
2. What problem does it solve?
3. What does it not do?
4. Safety warning.
5. Architecture in a few lines.
6. Requirements.
7. Quick start.
8. How to expose the lab safely for a remote vendor.
9. How to give the test credentials.
10. How to monitor.
11. What triggers alerts.
12. How to collect evidence.
13. How to tear down.
14. Threat model.
15. Limitations.
16. Security reporting.
17. Contributing.
18. License.

A user should be able to understand the safety model before running the first command.

## 30. SECURITY.md minimum

`SECURITY.md` must include:

- supported versions;
- how to report a vulnerability privately;
- a request not to disclose unresolved vulnerabilities publicly;
- what information is useful in a report;
- expected acknowledgement behavior;
- scope of the security policy.

Enable GitHub Private Vulnerability Reporting for the public repository when available.

## 31. Threat model minimum

`docs/THREAT_MODEL.md` must identify at least:

Assets:

- host system;
- lab database;
- synthetic data;
- lab credentials;
- evidence logs;
- webhook or notification secrets;
- source repository;
- CI credentials;
- release artifacts.

Threat actors:

- malicious or compromised third-party vendor;
- malicious contributor;
- compromised dependency;
- compromised GitHub Action;
- opportunistic internet scanner;
- user misconfiguration.

Primary failure modes:

- accidental production exposure;
- excessive database privileges;
- secret leakage;
- public database exposure;
- container breakout impact;
- host credential exposure;
- unsafe CI permissions;
- malicious dependency update;
- log injection;
- resource exhaustion;
- false-positive alert interpretation;
- incomplete teardown.

Each material threat should map to a prevention, detection, or containment control.

## 32. Contribution doctrine

Contributions are welcome, but security invariants are not negotiable.

Pull requests should:

- solve one clear problem;
- use minimal targeted changes;
- avoid unrelated refactors;
- include tests for changed behavior;
- update documentation when behavior changes;
- pass all CI checks;
- introduce no secrets;
- introduce no unnecessary dependency;
- preserve safe defaults.

Large architectural changes require an issue or design discussion before implementation.

Security fixes may use a private disclosure path.

## 33. Change doctrine

Prefer surgical changes.

Do not combine:

- formatting rewrites;
- dependency upgrades;
- architecture changes;
- security changes;
- feature additions

into one pull request unless they are inseparable.

Small diffs are easier to review, test, revert, and trust.

## 34. Versioning and releases

Use Semantic Versioning once public releases begin.

Before `1.0.0`, breaking changes are allowed but must be documented.

Every release requires:

- green CI;
- clean-clone E2E pass;
- no known release-blocking defects;
- no committed secrets;
- reviewed dependency changes;
- current documentation;
- current changelog;
- version consistency;
- release notes;
- checksums for downloadable artifacts;
- SBOM and provenance when the release pipeline supports them.

Security releases should clearly state:

- affected versions;
- fixed version;
- impact;
- mitigation;
- upgrade guidance.

## 35. License doctrine

Use an OSI-approved license.

For a permissive security tool intended for broad reuse, Apache License 2.0 is a strong default because it includes an explicit patent grant.

If a different license is chosen, document the reason.

Do not copy third-party code without verifying license compatibility and preserving required notices.

Use SPDX identifiers in files or package metadata where practical.

## 36. Release blocking conditions

Do not publish a release when any of the following is true:

- CI is failing;
- a security invariant is untested;
- the documented quick start does not work from a clean clone;
- the test user has more privileges than documented;
- the database is remotely exposed by default;
- a known secret is present in the working tree, Git history, image, logs, or release artifacts;
- a known critical vulnerability is reachable in the normal deployment path and has no accepted mitigation;
- evidence output contains credentials;
- teardown leaves the database or credentials active unexpectedly;
- documentation materially disagrees with implementation.

## 37. Fast v0.1 release scope

Do not overbuild the first release.

The initial public release needs:

- one-command or minimal-command Docker startup;
- synthetic data;
- one dedicated read-only vendor role;
- strict database permissions;
- query and connection logging;
- high-signal deviation alerts;
- evidence export;
- clean teardown;
- README;
- SECURITY.md;
- LICENSE;
- CONTRIBUTING.md;
- threat model;
- tests;
- CI;
- secret scanning;
- dependency update automation.

Do not block v0.1 on:

- web UI;
- hosted SaaS;
- Kubernetes;
- cloud-specific automation;
- multiple database engines;
- complex dashboards;
- plugin systems;
- user accounts;
- multi-tenant architecture.

Build the smallest system that proves the security model.

## 38. Definition of done

A change is done only when:

- implementation is complete;
- security invariants still hold;
- tests cover the changed behavior;
- negative tests exist for relevant security controls;
- lint and static checks pass;
- Docker E2E passes if the change touches runtime behavior;
- docs match reality;
- no secrets or generated junk were added;
- the diff is focused;
- the project still works from a clean clone.

A release is done only when a new user can clone it, follow the README, run the lab safely, observe the expected behavior, export evidence, destroy the environment, and understand the limitations without private maintainer knowledge.

## 39. Final operating principle

The project must be safe when the test subject behaves unexpectedly.

Do not trust the vendor.
Do not trust the network.
Do not trust configuration input.
Do not trust dependencies blindly.
Do not trust monitoring as an enforcement control.
Do not trust a successful demo as proof of security.

Trust controls that are explicit, testable, reproducible, observable, and fail closed.

## 40. Standards and references

This doctrine is informed by the following primary references:

- NIST Secure Software Development Framework, SP 800-218:
  https://csrc.nist.gov/pubs/sp/800/218/final

- OpenSSF Best Practices:
  https://best.openssf.org/

- OpenSSF Best Practices Badge:
  https://openssf.org/projects/best-practices-badge/

- OpenSSF Scorecard:
  https://scorecard.dev/

- SLSA v1.2:
  https://slsa.dev/spec/v1.2/

- OWASP Application Security Verification Standard:
  https://owasp.org/projects/asvs

- GitHub secure use reference for Actions:
  https://docs.github.com/en/actions/reference/security/secure-use

- GitHub repository security guidance:
  https://docs.github.com/en/repositories/creating-and-managing-repositories/best-practices-for-repositories

- GitHub branch protection:
  https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches

- GitHub artifact attestations:
  https://docs.github.com/en/actions/concepts/security/artifact-attestations

- Docker build best practices:
  https://docs.docker.com/build/building/best-practices/

- Docker rootless mode:
  https://docs.docker.com/engine/security/rootless/
