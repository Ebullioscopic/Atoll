#!/bin/sh
set -eu
SOURCE_ROOT="${SRCROOT:?}"
APP_CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"
APP_HELPERS="$APP_CONTENTS/Helpers"
COOLING_HELPER_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-com.Ebullioscopic.Atoll}.cooling"
COOLING_BUILD_DIR="${DERIVED_FILE_DIR:?}/AtollCooling"
mkdir -p "$APP_HELPERS" "$APP_CONTENTS/Resources" "$APP_CONTENTS/Library/LaunchDaemons" "$COOLING_BUILD_DIR"

# Match the app's architectures, including universal release builds.
for architecture in ${ARCHS:?}; do
    /usr/bin/xcrun --sdk macosx swiftc -O -sdk "${SDKROOT:?}" \
        -target "$architecture-apple-macosx${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
        "$SOURCE_ROOT/DynamicIsland/services/FanSMCCore.swift" \
        "$SOURCE_ROOT/DynamicIsland/services/FanControlWire.swift" \
        "$SOURCE_ROOT/DynamicIsland/services/CoolingXPC.swift" \
        "$SOURCE_ROOT/DynamicIsland/services/CoolingDaemonEngine.swift" \
        "$SOURCE_ROOT/FanHelper/Daemon.swift" \
        "$SOURCE_ROOT/FanHelper/main.swift" -o "$COOLING_BUILD_DIR/helper-$architecture"
done
set --
for architecture in $ARCHS; do set -- "$@" "$COOLING_BUILD_DIR/helper-$architecture"; done
/usr/bin/xcrun lipo -create "$@" -output "$APP_HELPERS/AtollFanHelper"
/bin/cp "$SOURCE_ROOT/THIRD_PARTY_FAN_CONTROL.md" "$APP_CONTENTS/Resources/THIRD_PARTY_FAN_CONTROL.md"
COOLING_PLIST="$APP_CONTENTS/Library/LaunchDaemons/$COOLING_HELPER_IDENTIFIER.plist"
/bin/cp "$SOURCE_ROOT/FanHelper/com.Ebullioscopic.Atoll.cooling.plist" "$COOLING_PLIST"
/usr/libexec/PlistBuddy -c "Set :Label $COOLING_HELPER_IDENTIFIER" "$COOLING_PLIST"
/usr/libexec/PlistBuddy -c "Delete :MachServices" "$COOLING_PLIST"
/usr/libexec/PlistBuddy -c "Add :MachServices dict" "$COOLING_PLIST"
/usr/libexec/PlistBuddy -c "Add :MachServices:$COOLING_HELPER_IDENTIFIER bool true" "$COOLING_PLIST"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    COOLING_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    if [ "$COOLING_SIGN_IDENTITY" = - ]; then
        /usr/bin/codesign --force --sign - --identifier "$COOLING_HELPER_IDENTIFIER" "$APP_HELPERS/AtollFanHelper"
    else
        /usr/bin/codesign --force --options runtime --timestamp --identifier "$COOLING_HELPER_IDENTIFIER" --sign "$COOLING_SIGN_IDENTITY" "$APP_HELPERS/AtollFanHelper"
    fi
fi
