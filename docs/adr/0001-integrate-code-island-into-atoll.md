---
status: accepted
---

# Integrate Code Island into Atoll as one application

Atoll will be the sole installed and running macOS application. Code Island's agent-session behavior will be integrated into Atoll rather than shipped as a separate app or background companion. We chose this over AtollExtensionKit-based two-process embedding because it would retain a second application lifecycle, while the existing declarative extension surface cannot own Code Island's local hook service, installer, state tracking, and native attention handoffs as one Atoll capability.

## Consequences

- Atoll owns startup, shutdown, windowing, updates, and user-facing settings.
- Code Island's standalone application shell and notch panel are not part of the merged product.
- Reused Code Island code and its MIT notice must be preserved within the GPL-3.0 Atoll distribution.
