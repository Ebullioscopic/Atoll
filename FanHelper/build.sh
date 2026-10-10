#!/bin/sh
set -eu
SOURCE_ROOT="${SRCROOT:?}"
APP_CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"
APP_HELPERS="$APP_CONTENTS/Helpers"
COOLING_BUILD_DIR="${DERIVED_FILE_DIR:?}/AtollCooling"
mkdir -p "$APP_HELPERS" "$APP_CONTENTS/Resources" "$COOLING_BUILD_DIR"

# Match the app's architectures, including universal release builds.
for architecture in ${ARCHS:?}; do
    /usr/bin/xcrun --sdk macosx swiftc -O -sdk "${SDKROOT:?}" \
        -target "$architecture-apple-macosx${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
        "$SOURCE_ROOT/DynamicIsland/services/FanSMCCore.swift" \
        "$SOURCE_ROOT/DynamicIsland/services/FanControlWire.swift" \
        "$SOURCE_ROOT/FanHelper/main.swift" -o "$COOLING_BUILD_DIR/helper-$architecture"
done
set --
for architecture in $ARCHS; do set -- "$@" "$COOLING_BUILD_DIR/helper-$architecture"; done
/usr/bin/xcrun lipo -create "$@" -output "$APP_HELPERS/AtollFanHelper"
/bin/cp "$SOURCE_ROOT/THIRD_PARTY_FAN_CONTROL.md" "$APP_CONTENTS/Resources/THIRD_PARTY_FAN_CONTROL.md"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    COOLING_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    if [ "$COOLING_SIGN_IDENTITY" = - ]; then
        /usr/bin/codesign --force --sign - "$APP_HELPERS/AtollFanHelper"
    else
        /usr/bin/codesign --force --options runtime --timestamp --sign "$COOLING_SIGN_IDENTITY" "$APP_HELPERS/AtollFanHelper"
    fi
fi
