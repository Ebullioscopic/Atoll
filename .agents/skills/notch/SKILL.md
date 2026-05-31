```markdown
# notch Development Patterns

> Auto-generated skill from repository analysis

## Overview

This skill introduces the core development patterns, coding conventions, and workflows used in the `notch` Swift codebase. It covers how to structure new features, UI tabs, bugfixes, and extension connection lifecycles, with practical examples and step-by-step guidance. Whether you're adding a new feature behind a user setting, creating a new UI tab, fixing regressions, or managing extension cleanup, this guide will help you contribute effectively and consistently.

## Coding Conventions

**File Naming:**  
- Use PascalCase for all Swift files.  
  _Example:_  
  ```
  ContentView.swift
  NotchAgentBusView.swift
  ExtensionRPCServer.swift
  ```

**Import Style:**  
- Use relative imports within the module.  
  _Example:_  
  ```swift
  import Foundation
  import SwiftUI
  ```

**Export Style:**  
- Use named exports for classes, structs, and functions.  
  _Example:_  
  ```swift
  public struct NotchAgentBusView: View { ... }
  ```

**Commit Messages:**  
- Follow the [Conventional Commits](https://www.conventionalcommits.org/) style.
- Prefixes: `fix:`, `feat:`, `perf:`, `build:`
- Keep messages concise (average ~58 characters).
  _Example:_  
  ```
  feat: add agent bus tab with settings toggle
  fix: correct tuple label in ContentView
  ```

## Workflows

### Feature Development with Settings Toggle
**Trigger:** When adding a new feature or major UI/UX improvement that should be user-togglable.  
**Command:** `/new-feature-toggle`

1. Implement the core feature logic in the relevant manager or component files.
2. Add new setting(s) to `models/Constants.swift` and/or `SettingsView`.
3. Wire up the toggle(s) in the Settings UI (`components/Settings/SettingsView.swift` or similar).
4. Gate the new logic behind Defaults keys and settings checks.
5. Update `ContentView.swift` and other root views to respect the new toggles.
6. Update or create subviews/components as needed.

_Example:_
```swift
// Constants.swift
struct Constants {
    static let enableNewFeature = "enableNewFeature"
}

// SettingsView.swift
Toggle("Enable New Feature", isOn: $settings.enableNewFeature)

// ContentView.swift
if settings.enableNewFeature {
    NewFeatureView()
}
```

---

### Feature Development: New Tab or View
**Trigger:** When adding a new top-level UI section or tab.  
**Command:** `/new-ui-tab`

1. Create a new SwiftUI view file for the tab (e.g., `components/Notch/NewTabView.swift`).
2. Add a new case to the tab selection enum (e.g., in `enums/generic.swift`).
3. Register the new tab in `TabSelectionView.swift`.
4. Wire up tab logic in `ContentView.swift` (using `switch`/`case` or navigation).
5. Add any required settings toggle or enable/disable logic.
6. Update `models/Constants.swift` if needed for tab configuration.

_Example:_
```swift
// enums/generic.swift
enum TabSelection {
    case home
    case agentBus
    case newTab // <-- new case
}

// TabSelectionView.swift
TabButton(title: "New Tab", selection: .newTab)

// ContentView.swift
switch selectedTab {
case .newTab:
    NewTabView()
}
```

---

### Bugfix Following Feature Refactor
**Trigger:** When a recent refactor or feature addition causes build errors or runtime bugs.  
**Command:** `/fix-after-refactor`

1. Identify the root cause of the bug (e.g., tuple label mismatch, binding error).
2. Update affected files to resolve the issue.
3. Test to ensure the fix resolves the regression.
4. Commit with a `fix:` prefix and reference to the refactor or feature.

_Example:_
```swift
// Before (bug: tuple label mismatch)
MyView(item: item, isActive: active)

// After (fix: correct label)
MyView(item: item, isActive: isActive)
```

---

### Extension Connection Lifecycle Cleanup
**Trigger:** When managing the lifecycle of extension connections and their associated UI state.  
**Command:** `/extension-cleanup`

1. Implement or update cleanup logic in `ExtensionRPCServer.swift` to handle disconnects.
2. Add or adjust grace period timers for delayed cleanup.
3. Ensure live activities are dismissed only when appropriate (after grace period, or when no other connections exist).
4. Cancel or reset grace tasks as needed on reconnect or server stop.
5. Update related UI (e.g., `NotchAgentBusView`) to reflect connection state.

_Example:_
```swift
// ExtensionRPCServer.swift
func handleDisconnect() {
    startGracePeriodTimer()
}

func startGracePeriodTimer() {
    graceTask = Task {
        try await Task.sleep(nanoseconds: gracePeriod)
        cleanupResources()
    }
}
```

## Testing Patterns

- Test files follow the pattern: `*.test.*`
- The specific testing framework is unknown; look for files like `FeatureName.test.swift`.
- Place tests alongside or near the code they cover.
- Use descriptive test names and cover both positive and negative cases.

_Example:_
```
DynamicIsland/components/Notch/AgentBusView.test.swift
```

## Commands

| Command               | Purpose                                                      |
|-----------------------|--------------------------------------------------------------|
| /new-feature-toggle   | Start a new feature behind a settings toggle                 |
| /new-ui-tab           | Add a new UI tab or top-level view                           |
| /fix-after-refactor   | Fix a regression or bug after a feature/refactor             |
| /extension-cleanup    | Implement or update extension connection lifecycle cleanup    |
```
