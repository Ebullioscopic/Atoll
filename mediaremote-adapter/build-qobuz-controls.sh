#!/bin/bash
set -euo pipefail
output="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/qobuz_controls"
mkdir -p "$(dirname "$output")" "${TEMP_DIR}/qobuz-module-cache"
binaries=()
for task_arch in ${ARCHS}; do
  binary="${TEMP_DIR}/qobuz_controls-${task_arch}"
  /usr/bin/xcrun swiftc -O -module-cache-path "${TEMP_DIR}/qobuz-module-cache" -target "${task_arch}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}" "${SRCROOT}/mediaremote-adapter/qobuz_controls.swift" -o "$binary"
  binaries+=("$binary")
done
/usr/bin/lipo -create "${binaries[@]}" -output "$output"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  /usr/bin/codesign --force --sign - "$output"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$output"
fi
