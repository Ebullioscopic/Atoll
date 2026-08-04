---
name: antigravity_codeisland_integration
description: Map Antigravity tool hook events to CodeIsland's ConfigInstaller.
globs: ["ConfigInstaller.swift"]
---
# Antigravity CodeIsland Integration Events & Matchers
- Antigravity uses `BeforeTool` and `AfterTool` for tool permission hooks, and `Notification` for non-blocking events.
- For `BeforeTool` and `AfterTool` events, explicitly assign the `"matcher": "*"` property in `ConfigInstaller` to route the prompts correctly into the Notch UI instead of silently bypassing.
