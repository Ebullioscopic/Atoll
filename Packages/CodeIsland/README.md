# Code Island subsystem

Code Island is an internal Swift package for Atoll. It is not a standalone
application. Atoll links its three library products and remains the only app,
window owner, settings owner, and update lifecycle.

Phases 1 through 5 establish four products:

- `CodeIslandCore` for provider-neutral, sanitized session metadata.
- `CodeIslandRuntime` for metadata storage, capability gating, read-only tool
  and adoption discovery, consent-bound activation ordering, conservative
  socket migration, a metadata-only Unix listener, receipt-owned repair, and
  exact managed Codex hook installation/removal.
- `CodeIslandUI` for Atoll-hosted setup/idle dashboard components. Imported
  rich presentation remains quarantined until Phase 6.
- `codeisland-bridge` for the signed bundled provider helper. Its Codex input
  path is deadline-bounded, reduces raw input to the metadata wire locally,
  and never returns a provider decision.

Phase 5 enables Codex Monitoring after an explicit confirmation sheet repeats
the current capability limits and every path in the consent-bound plan. Atoll
starts the listener before installing hooks, persists only sanitized session
metadata, resumes only a verified ownership receipt, and removes only exact
receipt-owned entries. Recognized legacy CodeIsland hook handlers are backed up
semantically, replaced to avoid duplicate raw delivery, and restored during
deactivation. Questions and approvals remain in Codex; Native attention and
the Phase 6 session/activity presentations remain gated.

Imported source and test candidates live under `Upstream` directories excluded
by SwiftPM. New focused implementations sit beside that quarantine; the
upstream monolithic installer and hook server remain excluded.

See [UPSTREAM.md](UPSTREAM.md) for provenance, exclusions, refresh procedure,
and verification commands. The frozen product contract is at
[`docs/code-island-integration-design.md`](../../docs/code-island-integration-design.md).
Phase evidence is recorded in the repository's `docs/code-island-phase-*-verification.md`
files.
