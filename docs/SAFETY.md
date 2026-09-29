# Safety

This project is a defensive test lab.

Use it only with infrastructure you own or are explicitly authorized to test.
The lab does not require scanning, exploitation, credential stuffing, service
disruption, or access to the third party's systems.

Use synthetic data only. Do not place real customer data, employer data,
production database dumps, production credentials, API tokens, private keys, or
other valuable secrets in the lab.

For remote testing, use a disposable VPS or VM. Do not expose the lab from a
corporate workstation, production server, VPN-connected host, or machine that
contains unrelated credentials.

PostgreSQL binds to loopback by default. Before remote exposure, obtain the
vendor's outbound source addresses and restrict the database port with the VPS
or cloud-provider firewall. Do not assume UFW alone protects Docker-published
ports.

Treat alerts as investigation signals. A denied query, metadata lookup, or
canary access attempt does not by itself establish malicious intent. Review the
full sequence, requested task, source address, and vendor explanation.

Export evidence before teardown when the activity matters. Evidence generated
by this project is an operational record, not a certified forensic
chain-of-custody system.
