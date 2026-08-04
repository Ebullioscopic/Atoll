// CodeIsland OpenClaw plugin
// version: v1

/**
 * @fileoverview CodeIsland Integration Plugin for OpenClaw (openclaw.ai).
 *
 * OpenClaw runs as a LaunchAgent Gateway daemon and loads this plugin
 * in-process (jiti, TypeScript ok). The plugin mirrors agent lifecycle /
 * tool events onto CodeIsland's Unix socket — the same wire contract as
 * the pi/omp extensions (codeisland-pi.ts / codeisland-omp.ts):
 *
 *   - fire-and-forget status events  -> /tmp/codeisland-<uid>.sock
 *   - blocking permission questions  -> ~/.codeisland/codeisland-bridge
 *
 * Loaded via openclaw.json:
 *   plugins.load.paths   += ["~/.openclaw/codeisland-plugin"]
 *   plugins.entries.codeisland.enabled = true
 *
 * No runtime imports from the "openclaw" package on purpose: hook names and
 * payloads changed between OpenClaw releases (before_agent_start vs
 * before_agent_run, session_end gaining a `reason`), so this file targets the
 * structural surface only. Unknown hook names are accepted-but-never-fired by
 * OpenClaw's registry, which makes dual-registration safe across versions.
 */

import { execFile, execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { connect } from "node:net";
import { homedir } from "node:os";
import { getuid } from "node:process";

// ── Minimal structural types (see header on why these are local) ─────────────

type HookHandler = (event: any, ctx: any) => unknown | Promise<unknown>;

interface OpenClawPluginApiLike {
  on?: (hookName: string, handler: HookHandler, opts?: { priority?: number }) => void;
  logger?: { info?: (m: string) => void; warn?: (m: string) => void };
}

/** Context fields shared by agent/tool/session hooks (all optional across versions). */
interface HookCtx {
  agentId?: string;
  sessionKey?: string;
  sessionId?: string;
  workspaceDir?: string;
}

// ── Socket / bridge constants ─────────────────────────────────────────────────

/** Unix socket path CodeIsland listens on (user-scoped). */
const userId = getuid?.() ?? 0;
const SOCKET_PATH = `/tmp/codeisland-${userId}.sock`;

/**
 * Bridge binary path. Used for blocking permission requests because Node's
 * half-close (`sock.end()`) causes NWConnection to close before the response
 * arrives on macOS; the bridge uses POSIX `shutdown(SHUT_WR)` which works.
 */
const BRIDGE_PATH = `${homedir()}/.codeisland/codeisland-bridge`;

/** Environment variable keys forwarded to CodeIsland for terminal detection. */
const ENV_KEYS = [
  "TERM_PROGRAM",
  "ITERM_SESSION_ID",
  "TERM_SESSION_ID",
  "TMUX",
  "TMUX_PANE",
  "KITTY_WINDOW_ID",
  "CMUX_SURFACE_ID",
  "CMUX_WORKSPACE_ID",
  "ZELLIJ_PANE_ID",
  "ZELLIJ_SESSION_NAME",
  "WEZTERM_PANE",
  "__CFBundleIdentifier",
] as const;

// ── Dangerous shell patterns (mirrors the pi/omp permission gate) ─────────────

const DANGEROUS_PATTERNS: RegExp[] = [
  /\brm\s+(-rf?|--recursive)/i,
  /\bsudo\b/i,
  /\b(chmod|chown)\b.*777/i,
];

function isDangerous(command: string): boolean {
  return DANGEROUS_PATTERNS.some((p) => p.test(command));
}

/** OpenClaw's shell tool is `exec`; accept bash/shell aliases defensively. */
const SHELL_TOOL_NAMES = new Set(["exec", "bash", "shell"]);

// ── Environment / TTY helpers ─────────────────────────────────────────────────

/** Collects relevant terminal environment variables (empty for the daemon). */
function collectEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  for (const key of ENV_KEYS) {
    if (process.env[key]) env[key] = process.env[key]!;
  }
  return env;
}

/**
 * Walks the process tree upward to find the controlling TTY. The Gateway is a
 * LaunchAgent daemon, so this normally returns null — kept for parity with the
 * pi/omp bridges (and for `openclaw gateway --dev` runs inside a terminal).
 */
function detectTty(): string | null {
  try {
    let pid = process.pid;
    for (let i = 0; i < 8; i++) {
      const out = execFileSync("ps", ["-o", "tty=,ppid=", "-p", String(pid)], {
        timeout: 1000,
      })
        .toString()
        .trim();
      const [tty, ppidStr] = out.split(/\s+/);
      if (tty && tty !== "??" && tty !== "?") {
        return tty.startsWith("/dev/") ? tty : `/dev/${tty}`;
      }
      const ppid = parseInt(ppidStr ?? "0", 10);
      if (!ppid || ppid <= 1) break;
      pid = ppid;
    }
  } catch {}
  return null;
}

// ── Socket communication ──────────────────────────────────────────────────────

/**
 * Sends a JSON payload to the CodeIsland socket (fire-and-forget).
 * Returns `false` silently when CodeIsland is not running.
 *
 * @param payload - Event object to serialise and send.
 * @returns `true` on successful delivery, `false` otherwise.
 */
function sendToSocket(payload: object): Promise<boolean> {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.write(JSON.stringify(payload));
        sock.end();
        resolve(true);
      });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3_000, () => {
        sock.destroy();
        resolve(false);
      });
    } catch {
      resolve(false);
    }
  });
}

/**
 * Sends a JSON payload via the bridge binary and waits for CodeIsland's response.
 * Used exclusively for blocking permission requests.
 *
 * @param payload    - Blocking request object.
 * @param timeoutMs  - Maximum wait time in milliseconds (default 30 s).
 * @returns Parsed response JSON, or `null` on error / timeout.
 */
function sendAndWaitResponse(
  payload: object,
  timeoutMs = 30_000,
): Promise<Record<string, unknown> | null> {
  return new Promise((resolve) => {
    if (!existsSync(BRIDGE_PATH)) {
      resolve(null);
      return;
    }
    try {
      const child = execFile(
        BRIDGE_PATH,
        [],
        { timeout: timeoutMs, maxBuffer: 1_048_576 },
        (error, stdout) => {
          if (error) {
            resolve(null);
            return;
          }
          try {
            resolve(JSON.parse(stdout));
          } catch {
            resolve(null);
          }
        },
      );
      child.stdin!.write(JSON.stringify(payload));
      child.stdin!.end();
    } catch {
      resolve(null);
    }
  });
}

// ── Lane resolution ───────────────────────────────────────────────────────────

/**
 * Derives a stable per-agent "lane" for CodeIsland session identity.
 *
 * OpenClaw's provider sessionId rotates on /new and /reset, and tool hooks only
 * carry a sessionKey ("agent:<agentId>:<channel>"). Folding everything onto the
 * agent id keeps one CodeIsland card per OpenClaw agent, stable across resets —
 * the daemon-appropriate analogue of one card per CLI process.
 */
function laneOf(ctx: HookCtx | undefined): string {
  if (ctx?.agentId) return ctx.agentId;
  const key = ctx?.sessionKey ?? "";
  if (key) {
    const parts = key.split(":");
    if (parts.length >= 2 && parts[0] === "agent" && parts[1]) return parts[1];
    return key;
  }
  return "main";
}

// ── Event builders ────────────────────────────────────────────────────────────

/**
 * Builds the base fields required on every CodeIsland event payload.
 *
 * @param lane  - OpenClaw agent lane (prefixed with `"openclaw-"`).
 * @param cwd   - Working directory shown on the session card.
 * @param extra - Event-specific fields merged into the base.
 * @returns Complete event payload ready for `sendToSocket`.
 */
function base(
  lane: string,
  cwd: string,
  extra: Record<string, unknown>,
  tty: string | null,
): Record<string, unknown> {
  return {
    session_id: `openclaw-${lane}`,
    _source: "openclaw",
    _ppid: process.pid,
    _env: collectEnv(),
    _tty: tty,
    _server_port: 0,
    cwd,
    ...extra,
  };
}

/** Capitalises the first character of a tool name for display. */
function displayToolName(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/** Extracts plain text from the last assistant message in an event.messages array. */
function extractLastAssistantText(messages: readonly unknown[]): string {
  const assistants = messages.filter(
    (m): m is { role: "assistant"; content: unknown } =>
      !!m &&
      typeof m === "object" &&
      (m as { role?: string }).role === "assistant",
  );
  const last = assistants.at(-1);
  if (!last) return "";
  const content = last.content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((c): c is { type: "text"; text: string } => c?.type === "text")
    .map((c) => c.text)
    .join("")
    .trim();
}

// ── Plugin ────────────────────────────────────────────────────────────────────

function register(api: OpenClawPluginApiLike): void {
  if (typeof api?.on !== "function") {
    api?.logger?.warn?.(
      "[codeisland] this OpenClaw build has no plugin hook API (api.on); plugin inactive",
    );
    return;
  }
  const on = api.on.bind(api);

  /** TTY path detected once at startup (null for the LaunchAgent daemon). */
  const tty = detectTty();

  /** Lanes for which CodeIsland has already received SessionStart. */
  const startedLanes = new Set<string>();
  /**
   * Lanes with a blocking PermissionRequest in flight. Non-lifecycle events
   * for these lanes are suppressed so CodeIsland's "answered externally"
   * heuristic doesn't auto-deny while the approval card is visible.
   */
  const pendingPermissionLanes = new Set<string>();
  /** Last workspaceDir seen per lane (tool hooks don't carry one). */
  const laneCwd = new Map<string, string>();
  /**
   * Prompt dedupe: `before_agent_start` (this release) and `before_agent_run`
   * (newer releases) are both registered; if a build fires both for one run,
   * drop the duplicate UserPromptSubmit.
   */
  const lastPrompt = new Map<string, { prompt: string; at: number }>();

  const defaultCwd = `${homedir()}/.openclaw/workspace`;

  function cwdOf(ctx: HookCtx | undefined, lane: string): string {
    const dir = ctx?.workspaceDir;
    if (typeof dir === "string" && dir.length > 0) {
      laneCwd.set(lane, dir);
      return dir;
    }
    return laneCwd.get(lane) ?? defaultCwd;
  }

  async function ensureSessionStarted(lane: string, cwd: string): Promise<void> {
    if (startedLanes.has(lane)) return;
    startedLanes.add(lane);
    await sendToSocket(base(lane, cwd, { hook_event_name: "SessionStart" }, tty));
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  on("session_start", async (_event: unknown, ctx: HookCtx) => {
    const lane = laneOf(ctx);
    // A fresh provider session (/new, /reset) restarts the lane's card state.
    startedLanes.delete(lane);
    await ensureSessionStarted(lane, cwdOf(ctx, lane));
  });

  on("session_end", async (_event: unknown, ctx: HookCtx) => {
    const lane = laneOf(ctx);
    if (!startedLanes.has(lane)) return;
    startedLanes.delete(lane);
    await sendToSocket(
      base(lane, cwdOf(ctx, lane), { hook_event_name: "SessionEnd" }, tty),
    );
  });

  // ── Agent lifecycle ────────────────────────────────────────────────────────

  const onAgentRunStart = async (
    event: { prompt?: unknown },
    ctx: HookCtx,
  ): Promise<void> => {
    const lane = laneOf(ctx);
    const cwd = cwdOf(ctx, lane);
    await ensureSessionStarted(lane, cwd);
    if (pendingPermissionLanes.has(lane)) return;

    const prompt = typeof event?.prompt === "string" ? event.prompt : "";
    const prev = lastPrompt.get(lane);
    const now = Date.now();
    if (prev && prev.prompt === prompt && now - prev.at < 2_000) return;
    lastPrompt.set(lane, { prompt, at: now });

    await sendToSocket(
      base(lane, cwd, { hook_event_name: "UserPromptSubmit", prompt }, tty),
    );
  };
  // This OpenClaw release fires `before_agent_start`; newer docs rename it to
  // `before_agent_run`. Unknown hook names are registered but never fired, so
  // dual registration is a safe cross-version bridge (dedupe above).
  on("before_agent_start", onAgentRunStart);
  on("before_agent_run", onAgentRunStart);

  on(
    "agent_end",
    async (
      event: { messages?: unknown[]; success?: boolean; error?: string },
      ctx: HookCtx,
    ) => {
      const lane = laneOf(ctx);
      const cwd = cwdOf(ctx, lane);
      await ensureSessionStarted(lane, cwd);
      if (pendingPermissionLanes.has(lane)) return;

      let lastAssistantMessage = extractLastAssistantText(
        Array.isArray(event?.messages) ? event.messages : [],
      );
      if (!lastAssistantMessage && event?.success === false && event?.error) {
        lastAssistantMessage = `Error: ${event.error}`;
      }

      await sendToSocket(
        base(lane, cwd, {
          hook_event_name: "Stop",
          last_assistant_message: lastAssistantMessage || undefined,
        }, tty),
      );
    },
  );

  // ── Tool calls ─────────────────────────────────────────────────────────────

  on(
    "before_tool_call",
    async (
      event: { toolName?: string; params?: Record<string, unknown> },
      ctx: HookCtx & { toolName?: string },
    ) => {
      const lane = laneOf(ctx);
      const cwd = cwdOf(ctx, lane);
      await ensureSessionStarted(lane, cwd);

      const rawName = event?.toolName ?? ctx?.toolName ?? "tool";
      const toolName = displayToolName(rawName);
      const params: Record<string, unknown> =
        event?.params && typeof event.params === "object" ? event.params : {};

      // Build a tool_input object appropriate for the tool type.
      const toolInput: Record<string, unknown> = { ...params };
      const command =
        typeof params.command === "string"
          ? params.command
          : typeof params.cmd === "string"
            ? params.cmd
            : undefined;
      if (SHELL_TOOL_NAMES.has(rawName) && command) {
        toolInput.patterns = [command];
      }
      if (typeof params.path === "string" && toolInput.file_path === undefined) {
        toolInput.file_path = params.path;
      }

      // Dangerous shell command → blocking PermissionRequest via the bridge.
      if (SHELL_TOOL_NAMES.has(rawName) && command && isDangerous(command)) {
        pendingPermissionLanes.add(lane);

        let response: Record<string, unknown> | null = null;
        try {
          response = await sendAndWaitResponse(
            base(lane, cwd, {
              hook_event_name: "PermissionRequest",
              tool_name: toolName,
              tool_input: toolInput,
            }, tty),
          );
        } finally {
          pendingPermissionLanes.delete(lane);
        }

        const decision = (
          response?.hookSpecificOutput as Record<string, unknown> | undefined
        )?.decision as Record<string, unknown> | undefined;

        if (decision?.behavior === "deny") {
          // OpenClaw's before_tool_call contract: block + blockReason.
          return { block: true, blockReason: "Blocked by CodeIsland" };
        }
        // Approved (or CodeIsland unreachable) — fall through to PreToolUse.
      }

      if (!pendingPermissionLanes.has(lane)) {
        await sendToSocket(
          base(lane, cwd, {
            hook_event_name: "PreToolUse",
            tool_name: toolName,
            tool_input: toolInput,
          }, tty),
        );
      }

      return undefined;
    },
  );

  on("after_tool_call", async (_event: unknown, ctx: HookCtx) => {
    const lane = laneOf(ctx);
    const cwd = cwdOf(ctx, lane);
    await ensureSessionStarted(lane, cwd);
    if (pendingPermissionLanes.has(lane)) return;

    await sendToSocket(base(lane, cwd, { hook_event_name: "PostToolUse" }, tty));
  });

  // ── Compaction ─────────────────────────────────────────────────────────────

  on("before_compaction", async (_event: unknown, ctx: HookCtx) => {
    const lane = laneOf(ctx);
    const cwd = cwdOf(ctx, lane);
    await ensureSessionStarted(lane, cwd);
    await sendToSocket(base(lane, cwd, { hook_event_name: "PreCompact" }, tty));
  });

  on("after_compaction", async (_event: unknown, ctx: HookCtx) => {
    const lane = laneOf(ctx);
    const cwd = cwdOf(ctx, lane);
    await ensureSessionStarted(lane, cwd);
    await sendToSocket(base(lane, cwd, { hook_event_name: "PostCompact" }, tty));
  });

  // ── Gateway lifecycle ──────────────────────────────────────────────────────

  on("gateway_stop", async () => {
    // Daemon shutting down — clear every lane's card instead of leaving
    // zombie sessions until CodeIsland's idle sweep catches them.
    const lanes = [...startedLanes];
    startedLanes.clear();
    await Promise.all(
      lanes.map((lane) =>
        sendToSocket(
          base(lane, laneCwd.get(lane) ?? defaultCwd, {
            hook_event_name: "SessionEnd",
          }, tty),
        ),
      ),
    );
  });
}

export default {
  id: "codeisland",
  name: "CodeIsland",
  description:
    "Bridges OpenClaw agent activity into the CodeIsland macOS notch panel.",
  register,
};
