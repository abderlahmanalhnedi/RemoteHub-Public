#!/bin/bash
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install the current Xcode from the Mac App Store."
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required because Command Line Tools do not include SwiftDataMacros."
  exit 1
fi

echo "Resolving pinned Swift packages..."
xcrun swift package resolve
echo "Bootstrap complete."
