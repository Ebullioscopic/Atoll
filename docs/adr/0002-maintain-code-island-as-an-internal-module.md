---
status: accepted
---

# Maintain Code Island as an internal module

Code Island will live inside the Atoll repository behind an independently maintainable source-module boundary. Its original provenance and a deliberate path for importing future upstream changes will be preserved. We chose this over an external package, which would couple one application to two source repositories, and direct source absorption, which would erase the boundary and make upstream reconciliation fragile. This module does not own a second application lifecycle; Atoll remains the host.

## Consequences

- Atoll owns the integration points and decides when upstream CodeIsland changes are imported.
- Code Island's runtime, state-management, installer, resources, and native views stay recognizable as one subsystem.
- Standalone application concerns must be separated from reusable feature behavior at the module boundary.
