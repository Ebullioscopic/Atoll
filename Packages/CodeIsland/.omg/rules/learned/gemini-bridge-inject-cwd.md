---
name: gemini-bridge-inject-cwd
description: >
  Neither --source gemini (agy CLI) nor --source google-antigravity include a
  cwd field in their hook payloads. The bridge must inject cwd from
  FileManager.default.currentDirectoryPath when the field is absent, otherwise
  all CodeIsland UI cards (approval prompts, session cards) show "Session"
  instead of the actual project folder name.
globs:
  - "Sources/CodeIslandBridge/main.swift"
---

## Pattern

Gemini-based CLIs (`agy`, Google Antigravity) do not include a `cwd` field in
the hook payload JSON they pipe to the bridge. CodeIsland's `SessionSnapshot`
uses `cwd` to derive the display name shown in all UI cards:

```swift
public var displayName: String {
    if let cwd = cwd {
        return (cwd as NSString).lastPathComponent
    }
    return "Session"  // fallback when cwd is absent
}
```

Without `cwd`, every approval card and session card shows `"Session"` instead
of e.g. `"codeisland-source"`.

### Fix — inject in the bridge before serialization

```swift
// After all env-var collection, before serializing enriched JSON:
if json["cwd"] == nil {
    json["cwd"] = FileManager.default.currentDirectoryPath
}
```

This must go **after** the source-specific adaptation blocks and **before**
`JSONSerialization.data(withJSONObject: json)` so the injected field is
included in what gets sent over the socket.

### Why not inject in the server?

The server (`HookServer`) receives the already-serialized payload and only sees
what the bridge sent. Injecting in the bridge is the correct layer.
