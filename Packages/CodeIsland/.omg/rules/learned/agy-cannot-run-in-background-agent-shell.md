---
name: agy-cannot-run-in-background-agent-shell
description: >
  The agy CLI cannot be used interactively from within a background/sandboxed
  agent terminal shell. It hangs because it tries to initialize interactive TTY
  components (spinners, terminal detection) and blocks waiting on stdin.
  Always instruct the user to test agy from their own interactive terminal.
globs: []
---

## Pattern

When debugging CodeIsland hooks or agy behavior, it is tempting to run
`~/.local/bin/agy "some prompt"` inside the agent's `run_command` tool to
trigger hook events and observe the notch UI.

**This does not work.** `agy` tries to:
1. Detect and initialize a TTY for rich terminal output (spinners, colors)
2. Read interactive input from stdin in some codepaths

Inside the agent's sandboxed shell there is no real TTY, causing `agy` to hang
indefinitely or error out before it even starts a session.

### How to test agy hook behavior

1. **User opens their own interactive terminal**
2. User runs: `~/.local/bin/agy "a prompt that triggers tool usage"`
3. Agent watches for events in the bridge log (`/tmp/codeisland-bridge.log`)
   or in the CodeIsland notch UI

### Simulating hook events from the agent shell

To test the bridge itself without needing `agy`, pipe a mock JSON payload
directly to the bridge binary:

```bash
CODEISLAND_DEBUG=1 echo '{
  "hook_event_name": "PreToolUse",
  "session_id": "test-sess",
  "tool_name": "Bash",
  "tool_input": {"command": "rm -rf bar"}
}' | /Users/matthewgold/.codeisland/codeisland-bridge \
      --source gemini \
      --event BeforeTool
```

This tests the bridge+server pipeline end-to-end without needing `agy`.
