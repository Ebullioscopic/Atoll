---
name: macos_app_bundle_overwrite
description: Best practice for replacing macOS application bundles and embedded helper binaries without file-locking issues.
globs: build.sh, Makefile
---

# macOS App Bundle Overwrite Pattern

When rebuilding and deploying macOS applications and their helper binaries:
1. Always terminate the running application process (`pkill -x AppName`) first to release file-system locks.
2. Delete the target `.app` directory entirely (`rm -rf /Applications/AppName.app`) instead of copying over it. Direct copy on top of an existing bundle can cause code signing discrepancies, library validation failures on launch, or silently keep old cached executables.
3. Copy the newly compiled `.app` bundle to its destination cleanly.
4. If the app embeds binaries that copy themselves to other directories (e.g., `~/.codeisland/codeisland-bridge`), overwrite them directly as well or force relaunch the app to trigger extraction.
