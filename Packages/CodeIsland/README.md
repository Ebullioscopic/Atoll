# Code Island subsystem

Code Island is an internal Swift package for Atoll. It is not a standalone
application and currently is not linked into Atoll's Xcode target.

Phases 1 and 2 establish four products:

- `CodeIslandCore` for provider-neutral, sanitized session metadata.
- `CodeIslandRuntime` for the metadata store, capability registry, and verified
  provider adapters. Its service lifecycle remains inert; Codex is explicitly
  limited to Monitoring because question and tool-failure observation do not
  yet have verified metadata-only contracts.
- `CodeIslandUI` for future Atoll-hosted presentation components; it remains a
  boundary marker in Phase 2.
- `codeisland-bridge` for the future bundled provider helper. Its Codex input
  path is deadline-bounded and non-owning, but Atoll does not install or invoke
  it yet.

Atoll does not link this package yet, and provider activation is unavailable.
Imported source and test candidates live under `Upstream` directories excluded
by SwiftPM; only the new metadata-safe Phase 2 sources are active beside that
quarantine.

See [UPSTREAM.md](UPSTREAM.md) for provenance, exclusions, refresh procedure,
and verification commands. The frozen product contract is at
[`docs/code-island-integration-design.md`](../../docs/code-island-integration-design.md).
Phase 2 evidence is recorded in
[`docs/code-island-phase-2-verification.md`](../../docs/code-island-phase-2-verification.md).
