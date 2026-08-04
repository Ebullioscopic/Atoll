---
status: accepted
---

# Keep agent decisions at the origin

When an agent is blocked on permission or user input, Atoll may automatically open and select Code Island, identify the waiting session, and offer a direct handoff to its terminal or native app. This attention handoff shows only the agent, project or session, waiting reason, and handoff action; command text and question content remain at the origin. Atoll will not present approve, deny, always-allow, option-selection, or free-text response controls. We chose a single decision authority because the originating tool contains the canonical context and trust boundary; duplicating its content or controls in Atoll would create competing state, expose sensitive context at the notch, increase the risk of an unintended authorization, and make provider-specific behavior inconsistent. Ordinary non-blocking activity does not switch panels automatically.

## Consequences

- Code Island is an attention-and-handoff surface, not an approval or answer control plane.
- Blocking hook integrations must notify Atoll and then defer to the provider's native prompt instead of waiting for an Atoll response.
- Active responder integrations, including CodeIsland's current Codex app-server question path, require an observation-safe redesign before reuse.
- Each supported provider must prove that pass-through preserves its native prompt; an unverified integration must not silently intercept a request.
