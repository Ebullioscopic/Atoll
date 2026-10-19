#!/bin/bash
# Policies and native UI renders by default; --live also controls fixture windows.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/dock-preview-verification
swiftc -parse-as-library \
    DynamicIsland/managers/DockPreview/DockPreviewModels.swift \
    DynamicIsland/managers/DockPreview/DockPreviewService.swift \
    DynamicIsland/managers/DockPreview/DockPreviewContent.swift \
    tests/DockPreviewRegression.swift \
    -o .build/dock-preview-verification/regression
.build/dock-preview-verification/regression --render .build/dock-preview-verification "$@"
