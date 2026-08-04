---
status: accepted
---

# Gate provider capabilities

Atoll will not treat coding-tool support as a single boolean. Each provider is enabled only at its highest tested capability: **monitoring** covers session state, meaningful transitions, and origin handoff; **native attention** additionally detects approvals or questions while proving that the provider's own prompt remains authoritative and usable. Settings will label the verified level and any limitations. We chose capability gating over withholding the entire merge until every upstream-recognized source reaches parity, because CodeIsland's current providers and variants expose materially different event contracts.

## Consequences

- A provider may ship with monitoring before native attention is available.
- Native attention requires provider-specific pass-through tests; absence of an Atoll response must never hang, approve, deny, or skip the native request.
- Newly imported upstream providers remain unavailable until their capability contract is tested.
- Product copy and setup UI must describe capabilities rather than make a blanket supported-tool count claim.
