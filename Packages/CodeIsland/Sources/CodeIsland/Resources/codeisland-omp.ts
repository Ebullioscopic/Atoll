// CodeIsland pi extension
// version: v2
// OMP-compatible install

/**
 * @fileoverview CodeIsland Integration Extension for Oh My Pi / OMP.
 *
 * This is the same socket bridge as codeisland-pi.ts, but imports OMP's
 * package scope so `omp` can load it from ~/.omp/agent/extensions.
 */

import { execFile, execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { connect } from "node:net";
import { homedir } from "node:os";
import { getuid } from "node:process";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";

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

// ── Dangerous bash patterns (mirrors permission-gate.ts) ──────────────────────

const DANGEROUS_PATTERNS: RegExp[] = [
  /\brm\s+(-rf?|--recursive)/i,
  /\bsudo\b/i,
  /\b(chmod|chown)\b.*777/i,
];

function isDangerous(command: string): boolean {
  return DANGEROUS_PATTERNS.some((p) => p.test(command));
}

// ── Environment / TTY helpers ─────────────────────────────────────────────────

/** Collects relevant terminal environment variables. */
function collectEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  for (const key of ENV_KEYS) {
    if (process.env[key]) env[key] = process.env[key]!;
  }
  return env;
}

/**
 * Walks the process tree upward to find the controlling TTY.
 * Cached at startup — pi's TTY does not change during a session.
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
 * Used exclusively for blocking permission/question requests.
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

// ── Event builders ────────────────────────────────────────────────────────────

/**
 * Builds the base fields required on every CodeIsland event payload.
 *
 * @param sessionId - Pi session UUID (prefixed with `"pi-"`).
 * @param cwd       - Current working directory.
 * @param extra     - Event-specific fields merged into the base.
 * @returns Complete event payload ready for `sendToSocket`.
 */
function base(
  sessionId: string,
  cwd: string,
  extra: Record<string, unknown>,
  tty: string | null,
): Record<string, unknown> {
  return {
    session_id: `pi-${sessionId}`,
    _source: "pi",
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
function extractLastAssistantText(
  messages: readonly unknown[],
): string {
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

// ── Extension ─────────────────────────────────────────────────────────────────

export default function codeislandExtension(pi: ExtensionAPI) {
  /** TTY path detected once at startup. */
  const tty = detectTty();

  /**
   * Session IDs for which a blocking PermissionRequest is currently in flight.
   * Non-lifecycle events for these sessions are suppressed to prevent CodeIsland's
   * "answered externally" heuristic from auto-denying while the card is visible.
   */
  const pendingPermissionSessions = new Set<string>();
  /** Sessions for which CodeIsland has already received SessionStart. */
  const startedSessions = new Set<string>();

  async function ensureSessionStarted(sessionId: string, cwd: string): Promise<void> {
    const sid = `pi-${sessionId}`;
    if (startedSessions.has(sid)) return;

    const sessionName = pi.getSessionName();
    await sendToSocket(
      base(sessionId, cwd, {
        hook_event_name: "SessionStart",
        ...(sessionName ? { session_title: sessionName } : {}),
      }, tty),
    );
    startedSessions.add(sid);
  }


  /**
   * Forwards an `ask` tool call to CodeIsland as an AskUserQuestion and waits
   * for the user's on-island answer (#244).
   *
   * @returns A block result carrying the answers when the user answered in
   *          CodeIsland, or `null` when the question should fall through to
   *          OMP's own TUI dialog (skipped, denied, or CodeIsland not running).
   */
  async function forwardAskToCodeIsland(
    event: { input: Record<string, unknown>; toolCallId: string },
    ctx: { cwd: string },
    sessionId: string,
    sid: string,
    tty: string | null,
  ): Promise<{ block: true; reason: string } | null> {
    const rawQuestions = Array.isArray(event.input.questions)
      ? (event.input.questions as Array<Record<string, unknown>>)
      : [];
    if (rawQuestions.length === 0) return null;

    // Map OMP's ask schema → Claude-style AskUserQuestion input.
    const questions = rawQuestions.map((q) => {
      const options = Array.isArray(q.options)
        ? (q.options as Array<Record<string, unknown>>)
            .map((o) => ({
              label: typeof o.label === "string" ? o.label : "",
              ...(typeof o.description === "string"
                ? { description: o.description }
                : {}),
            }))
            .filter((o) => o.label.length > 0)
        : [];
      return {
        question: typeof q.question === "string" ? q.question : "Question",
        ...(typeof q.id === "string" && q.id ? { header: q.id } : {}),
        multiSelect: q.multi === true,
        options,
      };
    });

    // CodeIsland keys answers by question text, deduping repeats with `_2`,
    // `_3`… suffixes — reproduce that here so we can translate back to ids.
    const usedKeys = new Set<string>();
    const answerKeys = questions.map(({ question }) => {
      let key = question;
      if (usedKeys.has(key)) {
        let suffix = 2;
        while (usedKeys.has(`${question}_${suffix}`)) suffix += 1;
        key = `${question}_${suffix}`;
      }
      usedKeys.add(key);
      return key;
    });

    pendingPermissionSessions.add(sid);
    let response: Record<string, unknown> | null = null;
    try {
      response = await sendAndWaitResponse(
        base(sessionId, ctx.cwd, {
          hook_event_name: "PermissionRequest",
          tool_name: "AskUserQuestion",
          tool_input: { questions },
          _pi_tool_call_id: event.toolCallId,
        }, tty),
        86_400_000, // waiting on a human — same 24h budget as PermissionRequest hooks
      );
    } finally {
      pendingPermissionSessions.delete(sid);
    }

    const decision = (
      response?.hookSpecificOutput as Record<string, unknown> | undefined
    )?.decision as Record<string, unknown> | undefined;
    if (decision?.behavior !== "allow") return null;

    const updatedInput = decision.updatedInput as
      | Record<string, unknown>
      | undefined;
    const answers = (updatedInput?.answers ?? {}) as Record<string, unknown>;

    const lines = rawQuestions.map((q, i) => {
      const id = typeof q.id === "string" && q.id ? q.id : `q${i + 1}`;
      const value = answers[answerKeys[i]];
      const text = Array.isArray(value)
        ? value.map(String).join(", ")
        : typeof value === "string"
          ? value
          : "";
      return `${id}: ${text || "(no answer)"}`;
    });

    return {
      block: true,
      reason:
        "The user already answered these questions through the CodeIsland desktop app. " +
        "Their answers:\n" +
        lines.join("\n") +
        "\nDo not ask again — proceed using these answers.",
    };
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  pi.on("session_start", async (_event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    await ensureSessionStarted(sessionId, ctx.cwd);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    await sendToSocket(
      base(sessionId, ctx.cwd, { hook_event_name: "SessionEnd" }, tty),
    );
    startedSessions.delete(`pi-${sessionId}`);
  });

  // ── Agent lifecycle ────────────────────────────────────────────────────────

  pi.on("before_agent_start", async (event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    const sid = `pi-${sessionId}`;
    await ensureSessionStarted(sessionId, ctx.cwd);

    if (pendingPermissionSessions.has(sid)) return;

    const prompt = event.prompt ?? "";
    await sendToSocket(
      base(sessionId, ctx.cwd, {
        hook_event_name: "UserPromptSubmit",
        prompt,
      }, tty),
    );
  });

  pi.on("agent_end", async (event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    const sid = `pi-${sessionId}`;
    await ensureSessionStarted(sessionId, ctx.cwd);

    if (pendingPermissionSessions.has(sid)) return;

    const lastAssistantMessage = extractLastAssistantText(event.messages);
    const sessionName = pi.getSessionName();

    await sendToSocket(
      base(sessionId, ctx.cwd, {
        hook_event_name: "Stop",
        last_assistant_message: lastAssistantMessage || undefined,
        ...(sessionName ? { session_title: sessionName } : {}),
      }, tty),
    );
  });

  // ── Tool calls ─────────────────────────────────────────────────────────────

  pi.on("tool_call", async (event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    const sid = `pi-${sessionId}`;
    await ensureSessionStarted(sessionId, ctx.cwd);
    const toolName = displayToolName(event.toolName);

    // Build a tool_input object appropriate for the tool type.
    const toolInput: Record<string, unknown> = { ...event.input };
    if (event.toolName === "bash") {
      const command = event.input.command as string | undefined;
      if (command) toolInput.patterns = [command];
    }
    if (event.toolName === "edit" || event.toolName === "write") {
      const path = event.input.path as string | undefined;
      if (path) toolInput.file_path = path;
    }

    // `ask` tool → mirror the question into CodeIsland's question UI (#244).
    // tool_call fires BEFORE the TUI dialog opens and OMP awaits this handler,
    // so we can hold the tool, let the user answer on the island (or watch/
    // phone), and feed the answers back by blocking the tool with a result
    // message. Skip/deny or an unreachable CodeIsland falls through to OMP's
    // own TUI dialog — graceful degradation, never a lost question.
    if (event.toolName === "ask") {
      const answered = await forwardAskToCodeIsland(event, ctx, sessionId, sid, tty);
      if (answered) return answered;
      return undefined;
    }

    // Dangerous bash → send blocking PermissionRequest via bridge.
    if (
      event.toolName === "bash" &&
      typeof event.input.command === "string" &&
      isDangerous(event.input.command)
    ) {
      pendingPermissionSessions.add(sid);

      const payload = base(sessionId, ctx.cwd, {
        hook_event_name: "PermissionRequest",
        tool_name: toolName,
        tool_input: toolInput,
        _pi_tool_call_id: event.toolCallId,
      }, tty);

      let response: Record<string, unknown> | null = null;
      try {
        response = await sendAndWaitResponse(payload);
      } finally {
        pendingPermissionSessions.delete(sid);
      }

      const behavior = (
        response?.hookSpecificOutput as Record<string, unknown> | undefined
      )?.decision as Record<string, unknown> | undefined;

      if (behavior?.behavior === "deny") {
        return { block: true, reason: "Blocked by CodeIsland" };
      }

      // Approved — fall through to normal PreToolUse event below.
    }

    // Non-blocking PreToolUse for all other tool calls.
    if (!pendingPermissionSessions.has(sid)) {
      await sendToSocket(
        base(sessionId, ctx.cwd, {
          hook_event_name: "PreToolUse",
          tool_name: toolName,
          tool_input: toolInput,
        }, tty),
      );
    }

    return undefined;
  });

  pi.on("tool_result", async (_event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    const sid = `pi-${sessionId}`;
    await ensureSessionStarted(sessionId, ctx.cwd);

    if (pendingPermissionSessions.has(sid)) return;

    await sendToSocket(
      base(sessionId, ctx.cwd, { hook_event_name: "PostToolUse" }, tty),
    );
  });

  // ── Compaction ─────────────────────────────────────────────────────────────

  pi.on("session_before_compact", async (_event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    await ensureSessionStarted(sessionId, ctx.cwd);
    await sendToSocket(
      base(sessionId, ctx.cwd, { hook_event_name: "PreCompact" }, tty),
    );
  });

  pi.on("session_compact", async (_event, ctx) => {
    const sessionId = ctx.sessionManager.getSessionId();
    await ensureSessionStarted(sessionId, ctx.cwd);
    await sendToSocket(
      base(sessionId, ctx.cwd, { hook_event_name: "PostCompact" }, tty),
    );
  });
}
