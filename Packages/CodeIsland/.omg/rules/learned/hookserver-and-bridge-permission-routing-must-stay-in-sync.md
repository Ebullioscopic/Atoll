---
name: hookserver-and-bridge-permission-routing-must-stay-in-sync
description: >
  Permission/blocking routing logic is split between two places: the bridge
  binary (main.swift isPermission flag, controls socket blocking) and HookServer
  (routeKind, controls UI routing). These must always be updated together. They
  have diverged before, causing one side to block while the other routes as a
  non-blocking event.
globs:
  - "Sources/CodeIslandBridge/main.swift"
  - "Sources/CodeIsland/HookServer.swift"
---

## Pattern

There are **two** independent places that decide whether an event is a
permission/blocking event:

| Location | Role |
|----------|------|
| `Sources/CodeIslandBridge/main.swift` — `isPermission` flag | Controls whether the bridge **blocks on the socket** waiting for a response (minutes/hours). Non-blocking events get a 1s recv timeout and return immediately. |
| `Sources/CodeIsland/HookServer.swift` — `routeKind(for:)` | Controls which UI handler is invoked: `.permission` → `handlePermissionRequest`, `.question` → `handleQuestion`, `.event` → `handleEvent` (fire-and-forget). |

### The failure mode

If you add permission support for a new source/event in the bridge but forget
to update `HookServer.routeKind`, the bridge will block correctly but the
server will route the event as a fire-and-forget `.event` — the approval card
never appears.

If you update `HookServer.routeKind` but forget the bridge, the server will
show an approval card but the bridge will time out after 1 second and the
decision will never reach `agy`.

### Rule

**Any change to permission routing must touch both files.** Write a unit test
for `HookServer.routeKind` whenever you add a new source:

```swift
func testNewSourcePreToolUseRoutesToPermission() async throws {
    let payload: [String: Any] = [
        "hook_event_name": "PreToolUse",
        "session_id": "test-sess",
        "_source": "new-source",
        "tool_name": "Bash",
        "tool_input": ["command": "rm -rf foo"]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let event = try XCTUnwrap(HookEvent(from: data))
    let kind = await MainActor.run { HookServer.routeKind(for: event) }
    XCTAssertEqual(kind, .permission)
}
```
