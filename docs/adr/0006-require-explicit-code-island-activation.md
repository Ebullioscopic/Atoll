---
status: accepted
---

# Require explicit Code Island activation

The Code Island tab will be present before activation, but Atoll will only discover available coding tools read-only and show setup guidance. Before installing hooks, plugins, or bridge files, Atoll must identify the selected tools, disclose the configuration paths it will change, and receive explicit user confirmation. Automatic verification and repair may run only for integrations the user has activated. We chose this over CodeIsland's current install-on-launch behavior because an Atoll installation or upgrade must not silently modify unrelated development-tool configurations.

## Consequences

- Starting or upgrading Atoll does not itself activate Code Island integrations.
- Newly supported coding tools are not enrolled automatically under an earlier consent.
- Setup, per-tool enablement, repair status, and uninstall must be visible and reversible.
- Removal must target only Atoll-managed entries and preserve unrelated user configuration.
