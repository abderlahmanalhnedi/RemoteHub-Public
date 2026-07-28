#!/bin/bash
set -euo pipefail

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift is required. Install the current stable Xcode."
  exit 1
fi

REMOTEHUB_SDK="$(xcrun --sdk macosx --show-sdk-path)"
if ! xcodebuild -version >/dev/null 2>&1 \
  && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
  REMOTEHUB_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

mkdir -p .build/core-module-cache

SOURCES=(
  RemoteHub/App/AppConstants.swift
  RemoteHub/Domain/Errors/RemoteHubError.swift
  RemoteHub/Domain/Models/ConnectionTypes.swift
  RemoteHub/Domain/Models/ProtocolSettings.swift
  RemoteHub/Domain/Protocols/TransportProtocols.swift
  RemoteHub/Domain/Validation/Validators.swift
  RemoteHub/Infrastructure/Keychain/CredentialStore.swift
  RemoteHub/Infrastructure/Logging/AppLog.swift
  RemoteHub/Infrastructure/Logging/Redactor.swift
  RemoteHub/Infrastructure/Processes/ProcessRunner.swift
  RemoteHub/Infrastructure/FTP/FTPListingParser.swift
  RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift
  RemoteHub/Infrastructure/RDP/RDPArgumentBuilder.swift
  RemoteHub/Infrastructure/SSH/HostKeyTrust.swift
  Verification/CoreSmoke.swift
)

SDKROOT="$REMOTEHUB_SDK" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/core-module-cache" \
swiftc \
  -sdk "$REMOTEHUB_SDK" \
  -swift-version 6 \
  -parse-as-library \
  "${SOURCES[@]}" \
  -o .build/remotehub-core-smoke

.build/remotehub-core-smoke
