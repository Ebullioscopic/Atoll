#!/bin/bash
# Policies and native UI renders by default; --live also controls fixture windows.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/dock-preview-verification
swiftc -parse-as-library \
    DynamicIsland/managers/DockPreview/DockPreviewModels.swift \
    DynamicIsland/managers/DockPreview/DockPreviewKeyboardMonitor.swift \
    DynamicIsland/managers/DockPreview/DockPreviewService.swift \
    DynamicIsland/managers/DockPreview/DockPreviewContent.swift \
    tests/DockPreviewRegression.swift \
    -o .build/dock-preview-verification/regression
.build/dock-preview-verification/regression --render .build/dock-preview-verification "$@"

# --installed opens Settings; --preview additionally enables the opt-in keyboard
# flow and verifies it against the installed build (requires its permissions).
if [[ " $* " == *" --installed "* ]]; then
    swiftc -parse-as-library tests/DockPreviewInstalledSmoke.swift -o .build/dock-preview-verification/installed-smoke
    .build/dock-preview-verification/installed-smoke "$@"
fi

# Opt-in local QuickTime fixture; enters/exits full screen and restores app state.
if [[ " $* " == *" --video "* ]]; then
    swiftc -parse-as-library \
        DynamicIsland/managers/DockPreview/DockPreviewModels.swift \
        DynamicIsland/managers/DockPreview/DockPreviewService.swift \
        tests/DockPreviewVideoRegression.swift \
        -o .build/dock-preview-verification/video-regression
    .build/dock-preview-verification/video-regression
fi
