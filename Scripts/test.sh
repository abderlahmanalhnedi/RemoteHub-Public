#!/bin/bash
set -euo pipefail

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full, current Xcode installation is required to compile SwiftData macros."
  echo "The Command Line Tools-only fallback can still be checked with: make core-check"
  exit 1
fi

xcrun swift test
