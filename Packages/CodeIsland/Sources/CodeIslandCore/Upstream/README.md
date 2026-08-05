# Core migration staging

These source files and tests are history-preserved candidates from CodeIsland
`v1.0.31`. They are deliberately excluded from `CodeIslandCore` in Phase 1.

The upstream models expose prompt, response, question, transcript, tool-input,
raw-payload, and provider-specific fields. Move code out of this directory only
after replacing those surfaces with the frozen metadata-only session contract.
Provider-specific discovery, filesystem scanning, and origin resolution belong
behind Runtime adapters rather than the provider-neutral Core API.
