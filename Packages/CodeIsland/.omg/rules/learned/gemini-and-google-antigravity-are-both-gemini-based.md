---
name: gemini-and-google-antigravity-are-both-gemini-based
description: >
  "--source gemini" (agy CLI, hooks in ~/.gemini/settings.json) and
  "--source google-antigravity" (hooks in ~/.gemini/config/hooks.json under
  "codeisland" key) are two different products but share the same hook payload
  structure. All permission routing, payload normalization, and cwd injection
  must handle both. Use a named boolean like isGeminiBasedSource rather than
  duplicating inline source checks.
globs:
  - "Sources/CodeIslandBridge/main.swift"
  - "Sources/CodeIsland/HookServer.swift"
  - "Sources/CodeIsland/ConfigInstaller.swift"
---

## Pattern

Two separate CLI products use Gemini's hook protocol and share payload structure:

| Source tag | Product | Hook config location | Event format |
|------------|---------|---------------------|--------------|
| `gemini` | Gemini CLI / `agy` | `~/.gemini/settings.json` → `hooks` key | `BeforeTool`, `AfterTool`, etc. in config; `PreToolUse` in JSON |
| `google-antigravity` | Google Antigravity IDE/CLI | `~/.gemini/config/hooks.json` → `codeisland` key | PascalCase `PreToolUse`, `PostToolUse`, `Stop` |

Despite different configs and hook-name conventions, both products:
- Send `hook_event_name: "PreToolUse"` in the actual JSON payload for tool events
- Do **not** include a `cwd` field
- Use `conversationId` instead of `session_id`
- Need their `PreToolUse` treated as a blocking permission event

### Correct pattern

Introduce a named variable and use it everywhere:

```swift
// In main.swift (bridge)
let isGeminiBasedSource = sourceTag == "google-antigravity" || sourceTag == "gemini"
    || effectiveSource == "google-antigravity" || effectiveSource == "gemini"

// In HookServer.swift
let isGeminiBasedSource = normalizedSource == "google-antigravity" || normalizedSource == "gemini"
```

### Anti-pattern

```swift
// Only covers one of the two — will miss the other
if sourceTag == "google-antigravity" && normalizedEventName == "PreToolUse" { ... }
```

### Scope of shared behavior

Both sources need:
1. `PreToolUse` → permission routing (blocking)
2. `cwd` injected from the bridge's working directory
3. Response translation: CodeIsland's `hookSpecificOutput.decision.behavior` → `{"decision": "allow"/"deny"}`
