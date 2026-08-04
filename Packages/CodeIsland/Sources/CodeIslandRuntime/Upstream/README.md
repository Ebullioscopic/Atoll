# Runtime migration staging

These files are history-preserved candidates from CodeIsland `v1.0.31`. They
are deliberately excluded from the `CodeIslandRuntime` target in Phase 1.

Move a file out of this directory only after adapting it to the frozen Atoll
contracts for explicit activation, immediate provider pass-through, and
metadata-only persistence. The original `HookServer` and installer behavior is
not safe to enable unchanged.
