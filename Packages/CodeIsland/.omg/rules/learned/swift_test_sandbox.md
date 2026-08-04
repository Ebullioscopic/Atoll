---
name: swift_test_sandbox
description: Workaround for macOS ModuleCache permissions during swift test.
globs: ["Package.swift", "*Tests.swift"]
---
# Swift Testing Sandbox Limitations (ModuleCache)
- Standard execution of `swift test` in the agent terminal sandbox fails on macOS due to sandboxed read/write restrictions on `/var/folders/` for Clang's ModuleCache.
- Always run `swift test` with `BypassSandbox: true` when testing Swift packages or Xcode projects.
