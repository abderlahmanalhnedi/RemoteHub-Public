# Public Release Audit

Audit date: 2026-07-28

This report covers the clean public source snapshot prepared from the private
RemoteHub repository. It is a release-readiness review, not an independent
security audit or certification.

## Repository status

- The source repository was confirmed private on GitHub.
- The source worktree was clean on `feat/bundled-freerdp`, with no staged,
  unstaged, or untracked changes at the start of preparation and again after
  validation.
- The source remote and Git history were not copied, rewritten, or modified.
- The public candidate was produced from tracked files only in a new sibling
  directory. It contains no inherited `.git` directory, branches, pull
  requests, tags, or commits.
- The public candidate is intended for a new repository named
  `RemoteHub-Public` with one `main` branch and one initial commit.

## Build status

The following commands completed successfully in the public candidate:

- `make bootstrap`
- `make build`

The native macOS app built successfully with the pinned Swift dependencies.
The development build intentionally contains no FreeRDP binary payload, so
bundled RDP remains unavailable. Xcode also reported that Hardened Runtime is
disabled for the local ad-hoc signing path; the documentation now states this
limitation explicitly.

## Test status

- `make test`: passed, 69 XCTest cases and 0 failures.
- `make ui-test`: passed on the first run, 1 UI test and 0 failures.
- `make core-check`: passed, 15 portable core smoke checks.

The automated suite does not establish production readiness or full
interoperability with every supported server implementation.

## Lint status

`make lint` passed. SwiftLint was not installed, so the repository's documented
fallback parsed every Swift source file and ran the 15 core smoke checks.

## Secret scan results

The private source workspace was scanned recursively except for its `.git`
directory. The public candidate was then scanned independently after cleanup.
Gitleaks and TruffleHog were not installed, so neither external scanner was
run. Manual review and pattern searches covered credentials, credential-like
assignments, keys and certificates, environment files, logs, exports, private
network ranges, hostnames, domains, email addresses, local paths, fingerprints,
and high-entropy identifiers.

No real credential, private key, certificate, access token, customer
identifier, internal hostname, or private-network address is present in the
public candidate.

Ignored generated output in the private workspace contained stale local build
paths and local-only test/run data, including a private-network test endpoint.
That generated output was not tracked, was not copied, and is excluded from
the public release.

Accepted false positives were reviewed individually:

- deliberately conspicuous fake credential values used by redaction and
  non-leak tests;
- deterministic synthetic SSH public-key and fingerprint fixtures documented
  as test-only data;
- demo-user absolute path fixtures used to test argument construction;
- credential-related field names, UI labels, security guidance, and redaction
  expressions required by the application's functionality;
- dependency checksums and pinned upstream commit identifiers; and
- the public author attribution and established application bundle namespace.

## Screenshot review

Every PNG under `docs/assets/screenshots/` was inspected at full resolution and
its available metadata was reviewed:

- `credential-editor.png`
- `new-connection.png`
- `host-key-prompt.png`
- `ssh-terminal.png`
- `session-controls.png`

The screenshots use demo identities, reserved example hostnames, localhost
where appropriate, and synthetic connection data. They do not expose a real
account, private server, customer, company, local workstation path,
notification, Finder sidebar, Dock, or unrelated desktop content. All five
screenshots are approved for inclusion.

## Documentation review

The public README now describes the implemented feature set, development build
workflow, FreeRDP payload boundary, and active-development status without
claiming an audit, certification, notarization, or production readiness.

Public `SECURITY.md` and `CONTRIBUTING.md` files were added. The security policy
directs vulnerability reports to GitHub's private reporting workflow and warns
contributors never to submit credentials, private keys, connection exports,
internal logs, or private infrastructure details.

Architecture, product, security, and user documentation were reviewed for
environment-specific claims, stale verification statements, draft language,
and overstated hardening. Internal plans, status notes, document-control
records, draft manual-test material, and obsolete verification baselines were
removed from the candidate.

## Excluded files

The public release excludes:

- the original `.git` directory and all inherited history;
- `.build`, `.swiftpm`, DerivedData, Xcode user state, and other generated
  build output;
- operating-system metadata, logs, temporary files, and local caches;
- environment files, connection or credential exports, and server lists;
- private keys, certificates, and signing material;
- FreeRDP binary payload artifacts; and
- private implementation plans, status reports, review notes, and obsolete
  verification records.

The expanded `.gitignore` protects the common generated, secret-bearing, and
export file patterns identified during this review.

## Remaining risks

- The code has not received an independent security assessment.
- Gitleaks and TruffleHog results are unavailable for this preparation.
- SwiftLint was unavailable; the repository fallback was used.
- No reviewed FreeRDP binary payload is included.
- The local app is ad-hoc signed; Hardened Runtime is disabled on that path,
  and no Developer ID-signed or notarized artifact was evaluated.
- The app is not App-Sandboxed.
- Live endpoint evidence is incomplete for several protocols and server
  implementations.
- Validation was performed on the available Apple silicon macOS host; a
  separate Intel validation was not performed.

## Manual follow-up items

- Add Gitleaks and TruffleHog to continuous integration and review every future
  finding before release.
- Confirm private vulnerability reporting remains enabled and test the
  reporting path without submitting sensitive data.
- Configure branch protection and review GitHub's public-repository secret
  scanning alerts.
- Complete license inventory and maintainer review before distributing a
  FreeRDP payload.
- Produce and verify a Developer ID-signed, Hardened Runtime-enabled, notarized
  distribution before describing the app as a supported binary release.
- Complete the outstanding live-protocol matrix and validate supported
  architectures in CI.

## Final recommendation

The reviewed source snapshot is suitable for publication as an
active-development open-source project, subject to the limitations above. It
must not be represented as independently audited, certified,
production-ready, or as a supported notarized binary distribution.

READY FOR PUBLIC RELEASE
