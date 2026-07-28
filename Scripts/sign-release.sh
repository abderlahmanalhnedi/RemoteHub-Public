#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /path/to/RemoteHub.app 'Developer ID Application: …'" >&2
  exit 64
fi

app_bundle="$1"
signing_identity="$2"
frameworks="$app_bundle/Contents/Frameworks"
helper="$app_bundle/Contents/Helpers/sdl-freerdp"

if [ ! -d "$app_bundle" ] || [ ! -x "$helper" ]; then
  echo "RemoteHub.app or bundled FreeRDP helper is missing." >&2
  exit 65
fi

sign_mach_o() {
  local candidate="$1"
  if /usr/bin/file "$candidate" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --options runtime \
      --timestamp \
      "$candidate"
  fi
}

while IFS= read -r nested_binary; do
  sign_mach_o "$nested_binary"
done < <(/usr/bin/find "$frameworks" -type f -print | LC_ALL=C /usr/bin/sort)

sign_mach_o "$helper"

/usr/bin/codesign \
  --force \
  --sign "$signing_identity" \
  --options runtime \
  --timestamp \
  "$app_bundle"

while IFS= read -r nested_binary; do
  if /usr/bin/file "$nested_binary" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign --verify --strict --verbose=2 "$nested_binary"
  fi
done < <(/usr/bin/find "$frameworks" -type f -print | LC_ALL=C /usr/bin/sort)
/usr/bin/codesign --verify --strict --verbose=2 "$helper"
/usr/bin/codesign --verify --strict --verbose=2 "$app_bundle"

echo "Signed nested libraries, FreeRDP helper, and RemoteHub.app with Hardened Runtime."
