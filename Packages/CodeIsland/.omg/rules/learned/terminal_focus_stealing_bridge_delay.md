---
name: terminal_focus_stealing_bridge_delay
description: Delay pattern in blocking hook bridges to prevent GUI notification Notch from stealing focus before the terminal prints the prompt.
globs: Sources/CodeIslandBridge/**/*.swift
---

# Terminal Focus Stealing Prevention

When a CLI tool triggers a blocking permission prompt (e.g., `PreToolUse`):
1. The notch server immediately opens a pop-up, taking focus or rendering over active windows.
2. If the bridge sends the event instantly, it can outrun the terminal TTY flush. The user sees a pop-up to approve something that isn't printed on screen yet.
3. Introduce a `250ms` delay (`usleep(250_000)`) in the bridge after receiving stdin but before connecting to the Unix socket for the blocking event.
4. This synchronizes prompt printing and Notch appearance, making it clear to the user what they are approving.
