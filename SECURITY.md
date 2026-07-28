# Security Policy

## Project status

RemoteHub is under active development. It has not received an independent
security audit, penetration test, or certification. There is no supported
production release or long-term support schedule.

Only the current `main` branch receives security fixes. Review the
[security overview](docs/security/security-overview.md) and
[known limitations](docs/known-limitations.md) before using the project.

## Report a vulnerability privately

Use GitHub's private vulnerability reporting form:

https://github.com/abderlahmanalhnedi/RemoteHub-Public/security/advisories/new

Include the affected revision, impact, reproduction steps, and the smallest
sanitized proof of concept needed to understand the issue. Allow the
maintainer time to investigate before public disclosure.

If the private reporting form is unavailable, do not open a public issue with
sensitive details. Contact the maintainer through a private channel and ask
for a secure reporting method.

## Do not submit sensitive data

Never submit or attach:

- credentials, passwords, passphrases, API keys, or access tokens;
- private keys, certificates containing private material, or SSH agent data;
- connection exports or credential exports;
- internal logs, diagnostic bundles, crash reports, or terminal history
  without a complete manual review;
- private hostnames, IP addresses, usernames, filesystem paths, fingerprints,
  customer data, or server inventory; or
- screenshots containing non-synthetic connection or desktop information.

Use reserved example networks, `localhost`, `example.com`, `*.example`, and
clearly synthetic test accounts in reproductions.

## Security scope

Reports about secret storage, import/export redaction, SSH host-key handling,
FTP/FTPS certificate behavior, FreeRDP invocation, subprocess boundaries, and
diagnostic redaction are in scope.

Dependency vulnerabilities should identify the affected dependency and explain
why RemoteHub reaches the vulnerable behavior. General hardening suggestions
without a concrete vulnerability can be filed as a normal public issue after
removing sensitive data.
