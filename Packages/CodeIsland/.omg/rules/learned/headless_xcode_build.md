---
name: headless_xcode_build
description: Handling actool IDE initialization failures in headless terminal sessions.
globs: ["build.sh"]
---
# Headless Xcode/Actool Build Failures
- Compiling Xcode projects containing `.xcassets` using `build.sh` or `xcodebuild` inside an agent's headless session often fails at `xcrun actool` with: `ibtoold failed IDE initialization: Loading a plug-in failed.`
- This does not mean the swift code failed to compile. The binaries are successfully linked. Inform the user to run the packaging/build step in their own interactive GUI terminal.
