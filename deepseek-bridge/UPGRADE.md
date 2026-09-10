# Upgrade an existing bridge after the native app is built

Run these commands from the repository root as the existing installation's user, without sudo. Check the local service before upgrading; the repository does not contain credentials or an installed service.

Inspect the existing installation and backend first:

```sh
python3 deepseek-bridge/upgrade.py --check
```

`--check` is read-only. It reports installation presence, whether the exact
launchd job is loaded, config-file presence, and the loopback `/health` status,
including `backend`, `configured`, and `protocol_version`. It does not read
`config.json`, print the key or launchd environment, or contact a model/provider.
It uses the existing plist's `--port` when present (otherwise 11435). HTTP is
restricted to `127.0.0.1`; proxies and redirects are not followed. An unreachable
backend reports null/false status fields rather than exposing raw errors. Exit
code is 0 for an installed bridge with healthy backend, otherwise 1; older
healthy bridges can report a null protocol version.

After parent review and the native build, upgrade with:

```sh
python3 deepseek-bridge/upgrade.py
```

The script requires an existing installation at
`~/Library/Application Support/AtollDeepSeekBridge` and the existing
`~/Library/LaunchAgents/local.atoll.deepseek-bridge.plist`, with the expected
label and installed Python bridge command. It refuses to install a missing
bridge or rewrite an unexpected plist.

Only these runtime files are replaced:

- `bridge.py`
- `pi_backend.py`
- `pi-tools.ts`
- `agent_tools.py`
- `tool_runner.py`
- `images.py`
- `jobs.py`

`config.json`, existing settings (including Pi settings), credentials,
configuration helpers, Atoll defaults, and the Image Access app/permissions
remain untouched. No image-access build, permission prompt, credential setup,
or `defaults` command is involved. The script itself stays in the checkout.

Before replacement, all existing allowlisted runtime files are copied into a
private timestamped directory under `runtime-backups` in the installation.
A checksum manifest records which runtime files did not previously exist.
Backups contain runtime code and this manifest only, never configuration or
keys. Their exact path is printed on success. Backups are retained for manual
rollback; they are not automatically pruned.

For a **loaded** bridge, the script stops only
`gui/<uid>/local.atoll.deepseek-bridge` before replacing files, then bootstraps
that same existing, unchanged plist. It checks for healthy protocol v2 after
the restart; `configured:false` does not cause failure or modify credentials.
Bootstrap tolerates launchd unload timing with up to five attempts, spaced
0.5 seconds apart, matching the installer. It stops retrying on the first
successful bootstrap, then performs the existing 12-second health check.
The same bounded retry policy applies when restarting the old runtime during
automatic recovery or manual rollback. Each launchctl invocation has a
15-second timeout; an invocation timeout or execution error fails immediately.
An installed but **unloaded** bridge is upgraded on disk and remains unloaded;
its output reports `restarted:false`.

After a live upgrade, rerun `--check` and record the printed backup path. For
the loaded v2 service, expect `installed:true`, `loaded:true`, and health fields
`healthy:true`, `backend:"pi"`, `protocol_version:2`. Record `configured`
separately: it reports whether the bridge has a nonempty key, not whether a
provider request has succeeded. A zero exit code from `--check` alone does not
prove a v2 upgrade, because a healthy legacy bridge also returns zero.

A restart interrupts active bridge chats/tools and clears in-memory sessions,
job results, and ID tombstones. Start fresh native session/request IDs after
an upgrade or rollback.

Replacement files are staged, then atomically renamed one at a time while the
loaded service is stopped. A process lock prevents concurrent upgrades.
Partial-copy, bootstrap, or health-verification failure triggers restoration of
the prior runtime and original loaded/unloaded state. If automatic recovery
fails, the error identifies the retained backup for manual recovery. A forced
process termination or power loss can also require manual rollback.
Failure messages include the sanitized failing action, launchctl return code
and bootstrap attempt count where available, or timeout/OS errno. Automatic
recovery preserves the original failure reason and reports a separate recovery
reason if needed. Raw launchctl stdout/stderr and environment values are never
printed.

To roll back, pass the printed backup path, or its timestamped directory name:

```sh
python3 deepseek-bridge/upgrade.py --rollback "<backup-path-printed-by-upgrade>"
```

Rollback validates the manifest/checksums and accepts only a direct backup
under this installation's `runtime-backups`. It restores the old runtime,
removes allowlisted files that were previously absent (for example, `jobs.py`
when reverting a legacy installation), and restarts only if the bridge was
loaded. Rollback first creates another timestamped backup of the current
runtime, so it is reversible as well. Legacy health is accepted after rollback.
Configuration and permissions are never restored from or copied into backups.

Offline tests:

```sh
cd deepseek-bridge
python3 -B -m unittest -v
node test_extension.mjs
```

Upgrade tests use temporary installations, a fake launchctl boundary, and an
optional ephemeral loopback health fixture. They do not run against the real
installed service or use a real key/API.
