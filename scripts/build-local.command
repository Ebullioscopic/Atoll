#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
    print -u2 'Please install Xcode in /Applications first.'
    exit 1
fi
xcodebuild -checkFirstLaunchStatus
xcodebuild build \
    -project "$project_dir/DynamicIsland.xcodeproj" \
    -scheme DynamicIsland \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$project_dir/../build/DerivedData" \
    CODE_SIGNING_ALLOWED=NO
