# Code Island subsystem

Code Island is an internal Swift package for Atoll. It is not a standalone
application. Atoll links its three library products and remains the only app,
window owner, settings owner, and update lifecycle.

Phases 1 through 4 establish four products:

- `CodeIslandCore` for provider-neutral, sanitized session metadata.
- `CodeIslandRuntime` for metadata storage, capability gating, read-only tool
  and adoption discovery, consent-bound activation ordering, conservative
  socket migration, and exact managed Codex hook installation/removal. Its
  live service lifecycle remains inert.
- `CodeIslandUI` for Atoll-hosted setup/idle dashboard components. Imported
  rich presentation remains quarantined until Phase 6.
- `codeisland-bridge` for the future bundled provider helper. Its Codex input
  path is deadline-bounded and non-owning, but Atoll does not install or invoke
  it yet.

Phase 4 shows live read-only discovery in Atoll Settings, including existing
CodeIsland artifacts, whitelisted feature preferences, recovery guidance, and
the exact paths a future activation would change. It exposes no activation
control. Codex remains Monitoring-only and activation-unavailable until Phase 5
ships and verifies the actual listener, bundled bridge, hook trust flow, and
event completions end to end.

Imported source and test candidates live under `Upstream` directories excluded
by SwiftPM. New focused implementations sit beside that quarantine; the
upstream monolithic installer and hook server remain excluded.

See [UPSTREAM.md](UPSTREAM.md) for provenance, exclusions, refresh procedure,
and verification commands. The frozen product contract is at
[`docs/code-island-integration-design.md`](../../docs/code-island-integration-design.md).
Phase evidence is recorded in the repository's `docs/code-island-phase-*-verification.md`
files.
