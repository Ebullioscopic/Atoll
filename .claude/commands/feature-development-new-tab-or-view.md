---
name: feature-development-new-tab-or-view
description: Workflow command scaffold for feature-development-new-tab-or-view in notch.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /feature-development-new-tab-or-view

Use this workflow when working on **feature-development-new-tab-or-view** in `notch`.

## Goal

Adds a new major UI tab or view (e.g., Agent Bus tab), including new SwiftUI view files, registration in tab selection, and wiring in main ContentView.

## Common Files

- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Notch/*.swift`
- `DynamicIsland/components/Tabs/TabSelectionView.swift`
- `DynamicIsland/enums/generic.swift`
- `DynamicIsland/models/Constants.swift`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Create new SwiftUI view file for the tab (components/Notch/ or similar).
- Add new case to enums/generic.swift or similar enum for tab selection.
- Register the new tab in TabSelectionView.swift.
- Wire up tab logic in ContentView.swift (switch/case or navigation).
- Add any required settings toggle or enable/disable logic.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.