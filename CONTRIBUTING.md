# Contributing to RemoteHub

RemoteHub is an early-stage macOS project. Contributions should keep changes
focused, preserve the documented security boundaries, and avoid claims that a
feature is production-ready or independently audited.

## Development requirements

- macOS 14 or newer
- A current full Xcode installation
- Git
- XcodeGen when regenerating `RemoteHub.xcodeproj`
- SwiftLint is optional; the repository provides a parse-and-smoke fallback

Set up and validate a checkout with:

```bash
make bootstrap
make build
make test
make lint
make core-check
```

Run `make ui-test` for changes that affect application launch, commands,
focus, text input, or other user-interface behavior.

If `project.yml` changes, run `make generate` and include the regenerated
`RemoteHub.xcodeproj` changes in the same pull request.

## Submission guidelines

1. Create a focused branch from `main`.
2. Add or update tests for behavior changes.
3. Update public documentation when behavior, limitations, or security
   boundaries change.
4. Run the relevant validation commands and report any unavailable tool.
5. Open a pull request describing the problem, the change, and verification.

Do not commit generated build output, user-specific Xcode state, FreeRDP
payload artifacts, connection exports, credentials, private keys,
certificates, logs, or environment files.

Tests and documentation must use synthetic data. Prefer `localhost`,
`127.0.0.1`, RFC 5737 example addresses, `example.com`, `*.example`, and demo
users. Review every screenshot at full resolution before submitting it.

## Security reports

Do not disclose a vulnerability in a public issue or pull request. Follow the
private process in [SECURITY.md](SECURITY.md), and never include real
credentials, keys, exports, internal logs, or private infrastructure details.

## Code and documentation expectations

- Keep secrets out of command-line arguments, logs, diagnostics, persistence,
  and exports.
- Preserve explicit SSH, TLS, and RDP trust decisions.
- Do not weaken certificate or host-key validation to make a test pass.
- Keep Swift concurrency warnings and errors visible.
- Use plain, factual documentation and distinguish implemented behavior from
  automated or live verification.

By contributing, you agree that your contribution is licensed under the
repository's [MIT License](LICENSE).
