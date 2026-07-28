#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 PAYLOAD_DIRECTORY [EXPECTED_ARCHITECTURE ...]" >&2
  exit 64
fi

payload_directory="$1"
shift
helper="$payload_directory/Helpers/sdl-freerdp"
frameworks="$payload_directory/Frameworks"
manifest="$payload_directory/manifest.json"
checksums="$payload_directory/SHA256SUMS"
notices="$payload_directory/THIRD-PARTY-NOTICES.md"

for required_path in "$helper" "$frameworks" "$manifest" "$checksums" "$notices"; do
  if [ ! -e "$required_path" ]; then
    echo "FreeRDP payload is incomplete: missing $required_path" >&2
    exit 65
  fi
done

if [ ! -x "$helper" ]; then
  echo "FreeRDP helper is not executable: $helper" >&2
  exit 65
fi

manifest_format_version="$(/usr/bin/plutil -extract formatVersion raw "$manifest")"
if [ "$manifest_format_version" != "1" ]; then
  echo "Unsupported FreeRDP payload manifest format: $manifest_format_version" >&2
  exit 65
fi
(
  cd "$payload_directory"
  /usr/bin/shasum -a 256 -c SHA256SUMS
)

dylibs=()
while IFS= read -r dylib; do
  dylibs+=("$dylib")
done < <(/usr/bin/find "$frameworks" -type f -name '*.dylib' -print)
if [ "${#dylibs[@]}" -eq 0 ]; then
  echo "FreeRDP payload contains no dynamic libraries." >&2
  exit 65
fi

mach_o_files=("$helper" "${dylibs[@]}")
for binary in "${mach_o_files[@]}"; do
  if ! /usr/bin/file "$binary" | /usr/bin/grep -q 'Mach-O'; then
    echo "Payload file is not a Mach-O binary: $binary" >&2
    exit 65
  fi

  binary_architectures="$(/usr/bin/lipo -archs "$binary")"
  for expected_architecture in "$@"; do
    if [[ " $binary_architectures " != *" $expected_architecture "* ]]; then
      echo "$binary is missing required architecture $expected_architecture (has: $binary_architectures)" >&2
      exit 65
    fi
  done

  while IFS= read -r dependency; do
    case "$dependency" in
      /System/Library/*|/usr/lib/*|@loader_path/*|@executable_path/*)
        ;;
      @rpath/*)
        dependency_name="${dependency#@rpath/}"
        if [ ! -e "$frameworks/$dependency_name" ]; then
          echo "$binary references missing bundled dependency $dependency" >&2
          exit 65
        fi
        ;;
      *)
        echo "$binary has a non-relocatable dependency: $dependency" >&2
        exit 65
        ;;
    esac
  done < <(/usr/bin/otool -L "$binary" | /usr/bin/awk 'NR > 1 { print $1 }')
done

if ! /usr/bin/otool -l "$helper" \
  | /usr/bin/awk '/cmd LC_RPATH/{getline; getline; print $2}' \
  | /usr/bin/grep -Fxq '@loader_path/../Frameworks'; then
  echo "FreeRDP helper is missing @loader_path/../Frameworks LC_RPATH." >&2
  exit 65
fi

echo "Verified FreeRDP payload: $payload_directory"
