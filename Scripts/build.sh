#!/bin/bash
set -euo pipefail

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full, current Xcode installation is required to build the macOS application."
  echo "The Command Line Tools-only fallback can still be checked with: make core-check"
  exit 1
fi

derived_data_path="${REMOTEHUB_DERIVED_DATA_PATH:-$(getconf DARWIN_USER_CACHE_DIR)com.alhnedi.RemoteHub/DerivedData}"
architecture="$(uname -m)"

xcodebuild \
  -project RemoteHub.xcodeproj \
  -scheme RemoteHub \
  -configuration Debug \
  -derivedDataPath "$derived_data_path" \
  -destination "platform=macOS,arch=$architecture" \
  build

echo "Application: $derived_data_path/Build/Products/Debug/RemoteHub.app"
