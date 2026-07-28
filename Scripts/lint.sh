#!/bin/bash
set -euo pipefail

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict
else
  echo "SwiftLint is optional and is not installed; parsing all Swift sources."
  find RemoteHub RemoteHubTests RemoteHubUITests Verification -name '*.swift' -print0 \
    | xargs -0 swiftc -frontend -parse
fi

./Scripts/core-check.sh
