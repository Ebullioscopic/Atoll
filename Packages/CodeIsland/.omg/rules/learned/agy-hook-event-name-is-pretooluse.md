---
name: agy-hook-event-name-is-pretooluse
description: >
  The agy/Gemini CLI hook config uses "BeforeTool" as the event name in
  settings.json (passing --event BeforeTool to the bridge as a fallback), but
  the actual JSON payload sent to the bridge contains hook_event_name:
  "PreToolUse". Because the bridge uses the JSON field first and the --event
  flag only as fallback, any code that intercepts BeforeTool must also handle
  PreToolUse from --source gemini.
globs:
  - "Sources/CodeIslandBridge/main.swift"
  - "Sources/CodeIsland/HookServer.swift"
  - "Sources/CodeIsland/ConfigInstaller.swift"
---

## Pattern

`agy` (Gemini CLI) hook payloads send `hook_event_name: "PreToolUse"` in the
JSON body even though `~/.gemini/settings.json` registers the hook under the
`BeforeTool` key and passes `--event BeforeTool` to the bridge.

The bridge reads `hook_event_name` from JSON first; `--event` is only a
fallback used when that field is absent. So `BeforeTool` is **never** what
arrives as the event name at runtime.

### Consequence

Code that checks `normalizedEventName == "PermissionRequest"` (which
`BeforeTool` maps to via EventNormalizer) will work for Gemini CLI sessions
started fresh, but any path that explicitly tests for `PreToolUse` to decide
blocking/permission routing must also include the `gemini` source, not just
`google-antigravity`.

### Fix Pattern

```swift
// CORRECT: covers both Gemini CLI sources
let isGeminiBasedSource = sourceTag == "google-antigravity" || sourceTag == "gemini"
    || effectiveSource == "google-antigravity" || effectiveSource == "gemini"
let isPermission = normalizedEventName == "PermissionRequest"
    || (isGeminiBasedSource && normalizedEventName == "PreToolUse")

// WRONG: misses --source gemini sessions from agy
let isPermission = normalizedEventName == "PermissionRequest"
    || (sourceTag == "google-antigravity" && normalizedEventName == "PreToolUse")
```
