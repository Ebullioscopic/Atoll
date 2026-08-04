---
status: accepted
---

# Persist session metadata only

Atoll will retain only the metadata required to identify an agent session, represent its state, and return the user to its origin: provider, project or session identity, navigation handles, state, and timestamps. Prompt text, assistant responses, commands, questions, answer options, tool input, and raw event payloads will not be persisted or exported. The runtime may parse sensitive fields transiently when a provider contract requires them, but must discard them after deriving the permitted state. We chose this over CodeIsland's richer session persistence because the merged product deliberately keeps canonical content in the originating tool.

## Consequences

- Existing CodeIsland prompt and response fields are not imported during guided adoption.
- Session files, preferences, logs, crash context, and diagnostics must use the same metadata-only projection.
- UI view models receive sanitized session summaries rather than raw hook events.
- A future history feature would require a new explicit privacy decision and migration.
