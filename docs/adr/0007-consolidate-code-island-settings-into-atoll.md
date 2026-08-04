---
status: accepted
---

# Consolidate Code Island settings into Atoll

Code Island will use Atoll's existing searchable settings window rather than retain its standalone settings navigation. A dedicated Code Island page will own activation, per-tool integrations, hook health and removal, session behavior, mascots, and sounds. Code Island actions belong in Atoll's existing Shortcuts page. Atoll remains the sole owner of launch at login, display selection, language, application appearance, updates, and About. Remote-host and Buddy settings are absent from the first merged release because those capabilities are deferred.

## Consequences

- CodeIsland's `SettingsWindowController` and top-level settings navigation are not reused.
- Reusable feature-specific controls may be adapted to Atoll's form and search conventions.
- A setting with an Atoll equivalent must be mapped to that existing setting rather than duplicated.
- Removing the Code Island feature settings must not remove Atoll's application-level preferences.
