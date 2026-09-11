# Native Atoll bridge protocol v2

The bridge binds **127.0.0.1 only**. All routes retain the Host allowlist
(`127.0.0.1` or `localhost`) and reject requests carrying an Origin header.
The legacy `/api/chat`, `/api/tags`, and chat commands remain available and use
an independent legacy session.

## Health

`GET /health` returns HTTP 200. Existing `status`, `backend`, `configured`, and
`model` fields remain; these fields are added:

```json
{"protocol_version":2,"capabilities":{"jobs":true,"sessions":true}}
```

## Start

`POST /atoll/chat`, with a JSON object:

```json
{
  "session_id":"DA139E8B-ACFE-4BD3-8B8E-FF14B26054B0",
  "request_id":"515AB1A3-5687-430A-9247-563998F8141E",
  "messages":[{"role":"user","content":"Describe this","images":["<base64>"]}],
  "thinking":true,
  "tools":true
}
```

- Both IDs and both boolean flags are required. UUIDs must use the hyphenated
  8-4-4-4-12 format; case-insensitive lookup is supported. `job_id` preserves
  the spelling of the first accepted `request_id` (including uppercase UUIDs).
- `messages` is the **complete user-visible history**, including the new user
  turn. Supply 1–2048 messages, with roles `system`, `user`, or `assistant` and
  string `content`. The last message must have role `user`.
- Optional `images` is an array on user messages: up to eight PNG/JPEG/GIF/WebP
  base64 strings per message, at most 16 MiB decoded per image. Invalid images
  are rejected before job admission. Empty arrays are allowed. Previous images
  must remain in the supplied history for image follow-ups.
- The request body needs Content-Length, must be nonempty, and cannot exceed
  48 MiB. Transfer-Encoding is unsupported. Body reads time out after 10 seconds.
- The configured model is used for text-only history. If **any** supplied turn
  contains an image, `vision_model` (default `deepseek-v4-flash-vision-exp`) is
  used, including for text-only follow-ups to earlier images.
- Flags override settings only for this job; they do not change legacy commands
  or another session's settings. Credentials come from bridge configuration.

Admission returns immediately after validation and worker creation, without
waiting for Pi startup, model output, or tools:

```http
HTTP/1.0 202 Accepted
```
```json
{"job_id":"515AB1A3-5687-430A-9247-563998F8141E","status":"pending","model":"deepseek-v4-flash-vision-exp"}
```

A session has at most one active job. Other sessions execute concurrently.
Retrying the same request ID and identical messages/flags is idempotent: pending
jobs return the same 202 admission shape; completed/failed jobs return HTTP 200
with the polling shape. Configuration changes do not rerun an existing ID.
Reusing the ID with different messages/flags returns 409. A cancelled ID returns
409; a completed/failed ID whose result expired returns 410. Neither starts work.

Missing API configuration and Pi/model failures after admission produce a
pollable `failed` job with an actionable `content` string.

## Poll and progress

`GET /atoll/sessions/{session_id}/jobs/{job_id}` returns HTTP 200:

```json
{
  "job_id":"515AB1A3-5687-430A-9247-563998F8141E",
  "status":"pending",
  "content":"Partial assistant text",
  "model":"deepseek-v4-flash-vision-exp",
  "tools":["read_file"],
  "phase":"tool_execution"
}
```

The six fields are always present. `status` is `pending`, `completed`, `failed`,
or `cancelled`. `phase` is `pending`, `starting`, `generating`, `thinking`,
`tool_execution`, `completed`, `failed`, or `cancelled`.

`content` starts empty, exposes only assistant text while pending, and becomes
the complete answer or failure message at completion. Thinking events update
`phase` without exposing reasoning. Pi's `message_end` replaces accumulated
text; a new assistant message clears the previous partial text. `tools` contains
unique recognized tool names in first-start order, sourced from Pi's existing
RPC events. Tool start/update events set `tool_execution`; tool end returns to
`generating`. Tool output and arguments are not returned.

Polling never launches work and does not extend session/result retention.
Unknown job/session pairs return 404; retired sessions and expired results
return 410.

## Stop, including stop-before-start

`POST /atoll/sessions/{session_id}/stop` with `{"job_id":"<UUID>"}`:

- Returns HTTP 200 with the six-field polling shape, `status` and `phase` both
  `cancelled`, and empty `content`. Known jobs retain their model/tool names.
- Only the identified job may be terminated. A different active job in that
  session, or an ID known only in another session, returns 409 unchanged.
- An unknown ID is recorded as cancelled even when its initial chat POST has
  not arrived. Polling it returns cancelled. A late start with that ID returns
  409. This does not close an unrelated idle client's memory.
- Stopping the latest completed job also returns cancelled and closes its
  retained Pi client. Stopping an older job cannot close a newer client's memory.
- Repeating stop is idempotent. Concurrent repeated stops wait for the same
  cancellation to finish before acknowledging.
- A new request ID may start in the same SID after stop; send full history.

Pi and its process group (including tools) are terminated, the worker is joined,
and client state is cleared **before the 200 acknowledgment**. Cancellation
covers construction, startup RPC, context restoration, prompt dispatch, and
blocked writes. Late results/events cannot replace cancelled state.

## Reset and retire the SID

`POST /atoll/sessions/{session_id}/reset` with `{}` returns HTTP 200:

```json
{"session_id":"da139e8b-acfe-4bd3-8b8e-ff14b26054b0","status":"reset"}
```

Reset retires the SID immediately, stops/joins that session's work, clears its
results and Pi client, and removes its state directory before acknowledgment.
Other native sessions and the legacy session are unaffected. Reset is also
valid before the session's first chat POST. Repeated resets are idempotent and
wait for an in-progress reset to finish.

**Always rotate to a new SID after reset.** Subsequent start/poll/stop calls for
the retired SID return 410. A late chat POST that began before reset but reaches
admission afterward is rejected; it cannot spawn work after the reset ACK.

## History restoration and lifecycle bounds

A matching live client continues with the latest user turn. When Pi must be
recreated after stop, idle cleanup, model/key changes, 64 turns, a transcript
mismatch, or bridge restart, all preceding supplied turns are restored through
the extension's `/atoll-context` RPC command. User/assistant roles and image
blocks are preserved; system text is added to the Pi system prompt. The latest
user turn is then submitted once. Restoration makes **no replay, summary, or
other model calls**. Native automatic retry and compaction are disabled.

No native transcript is written to disk; Pi runs with `--no-session`. Only
provider/settings files are written in `pi-native/{sid}` and removed on
stop/reset/idle cleanup. The bridge retains history fingerprints, rather than
copies of prior request bodies.

Default bounds:

| Resource | Limit / expiry |
| --- | --- |
| Live native sessions / workers | 16; excess admission returns 503 |
| Idle client/session | Removed after 30 minutes, checked every 30 seconds |
| Pi generation | 5 minutes, at most 12 tool executions |
| Whole job watchdog | 6 minutes including startup; checked every 30 seconds |
| Reusable Pi client | Rebuilt after 64 turns |
| Retained terminal results | Most recent 128 globally; 30-minute TTL |
| Answer / pending text | 1,048,576 Unicode characters; oversized final answers fail visibly |
| RPC event queue per client | 256 events with backpressure |
| Session identity ledger | 4096 SIDs per bridge process |
| Request identity ledger | 8192 session/job pairs per bridge process |

Cancellation and retirement fences last for the **bridge process lifetime**,
even after payload/session cleanup. Cancelled IDs remain pollable with compact
cancelled results. Ledgers never evict an ID to make space: new identities/jobs
at capacity return 503, while existing-ID stop/reset continue to work. Restart
clears the ledgers; clients should use fresh UUIDs after a bridge restart.

## Errors

Errors use `{"error":"<description>"}`:

| HTTP status | Meaning |
| --- | --- |
| 400 | Missing/malformed UUID, body, messages, image, or boolean flag |
| 403 | Origin/Host rejected |
| 404 | Unknown route or unknown job/session pair |
| 409 | Busy/stopping session, mismatched stop ID, cancelled ID, or conflicting duplicate |
| 410 | Retired SID or expired job result |
| 503 | Resource/identity capacity reached or bridge shutting down |

## Offline verification

From `deepseek-bridge`:

```sh
python3 -m unittest -v
node test_extension.mjs
```

Python tests use fake keys, fake Pi objects/subprocesses, and ephemeral loopback
HTTP servers. The TypeScript extension test loads the existing local Pi `jiti`
and `typebox` packages without launching Pi or a provider. Its default package
root is `/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent`; override
with `ATOLL_TEST_PI_ROOT` when needed. Tests do not install/reload the service.
