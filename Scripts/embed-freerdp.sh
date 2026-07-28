#!/bin/bash
set -euo pipefail

source_root="${SRCROOT:?SRCROOT is required}"
target_build_directory="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
contents_folder_path="${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH is required}"
resources_folder_path="${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is required}"
payload_directory="${REMOTEHUB_FREERDP_PAYLOAD_DIR:-$source_root/Vendor/FreeRDP/payload}"
app_bundle="$target_build_directory/$contents_folder_path"

if [ ! -d "$payload_directory" ]; then
  if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    echo "Release builds require a reviewed FreeRDP payload at $payload_directory" >&2
    exit 65
  fi
  echo "Development build: no reviewed FreeRDP payload was supplied; bundled RDP is unavailable."
  exit 0
fi

read -r -a expected_architectures <<< "${ARCHS:-$(uname -m)}"
"$source_root/Scripts/verify-freerdp-payload.sh" \
  "$payload_directory" \
  "${expected_architectures[@]}"

/bin/mkdir -p "$app_bundle/Contents/Helpers"
/bin/mkdir -p "$app_bundle/Contents/Frameworks"
/bin/mkdir -p "$target_build_directory/$resources_folder_path"
/usr/bin/ditto "$payload_directory/Helpers/sdl-freerdp" \
  "$app_bundle/Contents/Helpers/sdl-freerdp"
/usr/bin/ditto "$payload_directory/Frameworks" \
  "$app_bundle/Contents/Frameworks"
/usr/bin/ditto "$payload_directory/THIRD-PARTY-NOTICES.md" \
  "$target_build_directory/$resources_folder_path/FreeRDP-THIRD-PARTY-NOTICES.md"
/bin/chmod 0755 "$app_bundle/Contents/Helpers/sdl-freerdp"

echo "Embedded reviewed FreeRDP payload in $app_bundle"
