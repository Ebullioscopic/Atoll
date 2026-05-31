---
name: feature-development-with-settings-toggle
description: Workflow command scaffold for feature-development-with-settings-toggle in notch.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /feature-development-with-settings-toggle

Use this workflow when working on **feature-development-with-settings-toggle** in `notch`.

## Goal

Implements a new feature or major UI change, with all new functionality gated behind user-configurable settings toggles (typically in the Settings UI and via Defaults keys).

## Common Files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Settings/SettingsView.swift`
- `DynamicIsland/models/Constants.swift`
- `DynamicIsland/managers/*.swift`
- `DynamicIsland/components/**/*.swift`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Implement core feature logic in relevant manager/component files.
- Add new setting(s) to models/Constants.swift and/or SettingsView.
- Wire up toggles in Settings UI (components/Settings/SettingsView.swift or similar).
- Gate new logic behind Defaults keys and settings checks.
- Update ContentView.swift and other root views to respect the new toggles.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.