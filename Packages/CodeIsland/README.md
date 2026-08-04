# Code Island subsystem

Code Island is an internal Swift package for Atoll. It is not a standalone
application and currently is not linked into Atoll's Xcode target.

Phase 1 establishes four products:

- `CodeIslandCore` for provider-neutral models and normalization.
- `CodeIslandRuntime` for explicitly activated provider services.
- `CodeIslandUI` for Atoll-hosted reusable presentation components.
- `codeisland-bridge` for the future bundled provider helper.

The runtime and helper are deliberately inert. Imported runtime and UI source
candidates live under `Upstream` directories excluded by SwiftPM; they must be
adapted and verified before migration into a product target.

See [UPSTREAM.md](UPSTREAM.md) for provenance, exclusions, refresh procedure,
and verification commands. The frozen product contract is at
[`docs/code-island-integration-design.md`](../../docs/code-island-integration-design.md).
