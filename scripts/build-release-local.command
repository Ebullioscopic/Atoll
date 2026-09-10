#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -checkFirstLaunchStatus
xcodebuild build \
    -project "$project_dir/DynamicIsland.xcodeproj" \
    -scheme DynamicIsland \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$project_dir/../build/DerivedData" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
