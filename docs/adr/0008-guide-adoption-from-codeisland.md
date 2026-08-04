---
status: accepted
---

# Guide adoption from CodeIsland

When Atoll detects an existing CodeIsland installation, preference domain, hook entries, plugins, bridge files, or active socket listener, it will offer a guided adoption rather than silently importing or ignoring them. Detection is read-only. Atoll identifies the relevant integrations and feature preferences, asks the user to quit CodeIsland if it is running, and imports only the items the user confirms. Compatible existing hook paths may be preserved to avoid unnecessary tool-configuration rewrites. Atoll will never terminate or delete `CodeIsland.app` automatically.

## Consequences

- Adoption remains subject to the same explicit activation and per-tool consent as a fresh setup.
- Atoll must detect and prevent two listeners from competing for the CodeIsland socket.
- Imported settings are limited to feature-specific preferences that still have meaning in Atoll.
- The adoption flow must provide recovery guidance if the old app or hooks remain active.
